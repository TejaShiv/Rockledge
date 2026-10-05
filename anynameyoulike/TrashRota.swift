import SwiftUI
import UserNotifications

// MARK: - Model

/// A weekly rotation and nothing else.
///
/// `people` is the cycle, in order. The anchor says which of them holds which
/// week. Nothing is inferred from who actually took the bins out: the only
/// way the rotation changes is somebody saying so.
struct TrashRota: Codable {
    var people: [String] = ["Me"]
    var me: Int = 0
    var anchorMonday: Date = TrashRota.mondayOf(Date())
    var anchorIndex: Int = 0

    static var gregorian: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        return cal
    }

    static func mondayOf(_ date: Date) -> Date {
        let cal = gregorian
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return cal.startOfDay(for: start)
    }

    // MARK: Persistence

    static func load() -> TrashRota {
        Store.document.trashRota
    }

    func save() {
        Store.mutate { $0.trashRota = self }
    }

    /// Tolerant of a document missing keys, and of the collection records and
    /// balances an earlier version wrote, which are simply dropped.
    enum CodingKeys: String, CodingKey {
        case people, me, anchorMonday, anchorIndex
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }

        people = value(.people, ["Me"])
        me = value(.me, 0)
        anchorMonday = value(.anchorMonday, TrashRota.mondayOf(Date()))
        anchorIndex = value(.anchorIndex, 0)
    }

    // MARK: The rotation

    var currentWeek: Int { weekIndex(of: Date()) }

    func weekIndex(of date: Date) -> Int {
        let days = Self.gregorian.dateComponents(
            [.day], from: anchorMonday, to: Self.mondayOf(date)
        ).day ?? 0
        return Int((Double(days) / 7).rounded())
    }

    func person(weeksAhead: Int = 0) -> String {
        guard !people.isEmpty else { return "—" }
        let n = people.count
        let index = ((anchorIndex + currentWeek + weeksAhead) % n + n) % n
        return people[index]
    }

    var thisWeek: String { person() }
    var lastWeek: String { person(weeksAhead: -1) }
    var nextWeek: String { person(weeksAhead: 1) }

    var isMyWeek: Bool {
        guard people.indices.contains(me) else { return false }
        return thisWeek == people[me]
    }

    // MARK: Setting a turn

    /// Puts `name` on the week `weeksAhead` from now by moving them to that
    /// slot in the cycle, leaving everybody else in the order they were in.
    ///
    /// Only the person named moves. Setting next week does not disturb this
    /// week, and setting last week disturbs neither — the rest of the cycle
    /// closes up around the change rather than being rewritten from it.
    mutating func setPerson(_ name: String, weeksAhead: Int) {
        guard people.count > 1, people.contains(name) else { return }
        let n = people.count

        // The cycle as it currently stands, read off from this week forward.
        var cycle = (0..<n).map { person(weeksAhead: $0) }
        cycle.removeAll { $0 == name }

        let slot = ((weeksAhead % n) + n) % n
        cycle.insert(name, at: min(slot, cycle.count))

        people = cycle
        anchorMonday = Self.mondayOf(Date())
        anchorIndex = 0
        save()
    }

    mutating func setCurrent(to index: Int) {
        guard people.indices.contains(index) else { return }
        setPerson(people[index], weeksAhead: 0)
    }

    // MARK: Changing the list

    /// Pins the anchor to whoever holds the current turn, so that changing
    /// the shape of the list does not shuffle everyone along.
    private mutating func rephase(onto name: String?) {
        anchorMonday = Self.mondayOf(Date())
        anchorIndex = name.flatMap { people.firstIndex(of: $0) } ?? 0
    }

    /// Added to the end of the cycle, so they come up when it reaches them.
    /// Use the turn pickers to put them somewhere else.
    mutating func addPerson(_ name: String) {
        guard !people.contains(name) else { return }
        let keep = people.isEmpty ? nil : person(weeksAhead: 0)
        people.append(name)
        rephase(onto: keep)
        save()
    }

    mutating func removePerson(at index: Int) {
        guard people.count > 1, people.indices.contains(index) else { return }

        let removed = people[index]
        let keep = person(weeksAhead: 0)
        let next = person(weeksAhead: 1)

        people.remove(at: index)
        if index == me {
            me = 0
        } else if index < me {
            me -= 1
        }

        rephase(onto: keep == removed ? next : keep)
        save()
    }
}


// MARK: - Notifications

enum TrashReminder {
    private static let prefix = "trashNight"
    private static let enabledKey = "trashReminderOn"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Each notification carries a name, so they are scheduled individually
    /// rather than as one repeating request. Refreshed every launch.
    static func reschedule(_ rota: TrashRota) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        )

        guard isEnabled, !rota.people.isEmpty else { return }

        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2

        let now = Date()
        let currentMonday = TrashRota.mondayOf(now)
        var day = cal.startOfDay(for: now)
        var made = 0
        var guardRail = 0

        while made < 12 && guardRail < 60 {
            guardRail += 1
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day

            let weekday = cal.component(.weekday, from: day)
            guard weekday == 1 || weekday == 4 else { continue }   // Sunday or Wednesday

            var parts = cal.dateComponents([.year, .month, .day], from: day)
            parts.hour = 20
            parts.minute = 0
            guard let fire = cal.date(from: parts), fire > now else { continue }

            let collection = cal.date(byAdding: .day, value: 1, to: day) ?? day
            let targetMonday = TrashRota.mondayOf(collection)
            let weeks = (cal.dateComponents(
                [.day], from: currentMonday, to: targetMonday
            ).day ?? 0) / 7

            let who = rota.person(weeksAhead: weeks)
            let mine = rota.people.indices.contains(rota.me) && who == rota.people[rota.me]

            let content = UNMutableNotificationContent()
            content.title = "Bins out tonight"
            content.body = mine
                ? "Your week. Take them out before bed."
                : "\(who)'s week."
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: cal.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: fire
                ),
                repeats: false
            )

            try? await center.add(
                UNNotificationRequest(
                    identifier: "\(prefix)-\(Int(fire.timeIntervalSince1970))",
                    content: content,
                    trigger: trigger
                )
            )
            made += 1
        }
    }
}

// MARK: - Top strip

struct TrashBar: View {
    let rota: TrashRota
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(
                        rota.isMyWeek ? Palette.redHot.opacity(0.9) : Palette.bone.opacity(0.35)
                    )

                Text(rota.isMyWeek ? "your week" : rota.thisWeek.lowercased())
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(Palette.bone.opacity(0.75))

                Spacer()

                Text("mon · thu")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(Palette.bone.opacity(0.28))

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Palette.bone.opacity(0.2))
            }
            .padding(.horizontal, 18)
            .frame(height: 42)
            .background(
                Capsule()
                    .fill(Palette.steel)
                    .overlay(
                        Capsule().strokeBorder(
                            Palette.red.opacity(rota.isMyWeek ? 0.5 : 0.18),
                            lineWidth: 1
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheet

struct TrashSheet: View {
    @Binding var rota: TrashRota
    let haptics: GrainHaptics
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var remindersOn = TrashReminder.isEnabled
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.inkLow, Palette.ink],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                SheetHeader(title: "trash", showRefresh: false) {} onClose: {
                    dismiss()
                }

                ScrollView {
                    VStack(spacing: 18) {
                        weekPanel
                        turnPanel
                        peoplePanel
                        remindToggle
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
    }

    private var weekPanel: some View {
        VStack(spacing: 14) {
            Text(rota.thisWeek)
                .font(.system(size: 42, weight: .heavy).width(.expanded))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(Palette.bone)

            Text("this week")
                .font(.system(size: 9, weight: .black))
                .tracking(1.6)
                .foregroundStyle(Palette.bone.opacity(0.3))

            HStack(spacing: 30) {
                StatPill(rota.lastWeek, "last week")
                StatPill(rota.nextWeek, "next week")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .glassBackdrop(cornerRadius: 28, tint: Palette.bone.opacity(0.06))
    }

    /// Says who is on which week outright. Each picker moves only the person
    /// it names; the cycle carries on from there through the rotation list.
    private var turnPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("whose turn")
                .font(.system(size: 9, weight: .black))
                .tracking(1.6)
                .foregroundStyle(Palette.bone.opacity(0.3))

            turnRow("last week", offset: -1, person: rota.lastWeek)
            turnRow("this week", offset: 0, person: rota.thisWeek)
            turnRow("next week", offset: 1, person: rota.nextWeek)

            Text("sets that week only, then cycles on through the rotation")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.bone.opacity(0.28))
                .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackdrop(cornerRadius: 28, tint: Palette.bone.opacity(0.06))
    }

    private func turnRow(_ label: String, offset: Int, person: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.bone.opacity(0.55))
                .frame(width: 78, alignment: .leading)

            PersonMenu(people: rota.people, selection: person) { name in
                haptics.soft()
                rota.setPerson(name, weeksAhead: offset)
                Task { await TrashReminder.reschedule(rota) }
            }

            Spacer()
        }
    }

    private var peoplePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("rotation")
                .font(.system(size: 9, weight: .black))
                .tracking(1.6)
                .foregroundStyle(Palette.bone.opacity(0.3))

            ForEach(Array(rota.people.enumerated()), id: \.offset) { index, name in
                HStack(spacing: 10) {
                    Button {
                        haptics.soft()
                        rota.setCurrent(to: index)
                        Task { await TrashReminder.reschedule(rota) }
                    } label: {
                        Image(systemName: name == rota.thisWeek
                              ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(
                                name == rota.thisWeek
                                ? Palette.redHot.opacity(0.9)
                                : Palette.bone.opacity(0.25)
                            )
                    }
                    .buttonStyle(.plain)

                    Text(name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.bone.opacity(0.85))

                    if index == rota.me {
                        Text("you")
                            .font(.system(size: 8, weight: .black))
                            .tracking(1.2)
                            .foregroundStyle(Palette.bone.opacity(0.3))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Palette.steel))
                    } else {
                        Button {
                            haptics.soft()
                            rota.me = index
                            rota.save()
                            Task { await TrashReminder.reschedule(rota) }
                        } label: {
                            Text("that's me")
                                .font(.system(size: 8, weight: .black))
                                .tracking(1.2)
                                .foregroundStyle(Palette.bone.opacity(0.25))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if rota.people.count > 1 {
                        Button {
                            haptics.soft()
                            remove(at: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Palette.bone.opacity(0.25))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }

            HStack(spacing: 10) {
                TextField("add a name", text: $newName)
                    .focused($nameFocused)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.bone)
                    .tint(Palette.redHot)
                    .submitLabel(.done)
                    .onSubmit { add() }

                Button {
                    add()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .black))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Palette.red))
                        .foregroundStyle(Palette.bone)
                }
                .buttonStyle(.plain)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 4)

            Text("tap a circle to say whose turn it actually is")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.bone.opacity(0.28))
                .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackdrop(cornerRadius: 28, tint: Palette.bone.opacity(0.06))
    }

    private var remindToggle: some View {
        Toggle(isOn: $remindersOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text("remind me")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.bone.opacity(0.85))
                Text("sunday and wednesday, 8pm")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.bone.opacity(0.3))
            }
        }
        .tint(Palette.red)
        .padding(20)
        .glassBackdrop(cornerRadius: 28, tint: Palette.bone.opacity(0.06))
        .onChange(of: remindersOn) { _, value in
            TrashReminder.isEnabled = value
            haptics.soft()
            Task { await TrashReminder.reschedule(rota) }
        }
    }

    private func add() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !rota.people.contains(trimmed) else { return }
        rota.addPerson(trimmed)
        newName = ""
        nameFocused = false
        haptics.commit()
        Task { await TrashReminder.reschedule(rota) }
    }

    private func remove(at index: Int) {
        rota.removePerson(at: index)
        Task { await TrashReminder.reschedule(rota) }
    }
}

// MARK: - Name picker

struct PersonMenu: View {
    let people: [String]
    let selection: String
    let onPick: (String) -> Void

    var body: some View {
        Menu {
            ForEach(people, id: \.self) { name in
                Button {
                    onPick(name)
                } label: {
                    if name == selection {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.bone.opacity(0.9))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Palette.bone.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(Palette.steel))
        }
        .buttonStyle(.plain)
    }
}
