import SwiftUI
import UserNotifications

// MARK: - Model

/// Who actually did a collection.
///
/// Only who did it is stored. Who was *due* is answered by the phase at the
/// time of asking, so a record can never contradict the rotation: re-phasing
/// re-reads every record against the new order rather than leaving stale
/// stamps behind. A record naming the person who was due is no record at all
/// and is dropped.
struct TrashRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date          // start of the collection day
    var didIt: String
}

/// One Monday or Thursday collection, with who was due and who is on record
/// as having done it.
struct TrashCollection: Identifiable {
    var date: Date
    var due: String
    var didIt: String

    var id: Date { date }
    var isCorrected: Bool { didIt != due }
}

struct TrashRota: Codable {
    var people: [String] = ["Me"]
    var me: Int = 0
    var anchorMonday: Date = TrashRota.mondayOf(Date())
    var anchorIndex: Int = 0

    /// Collections that did not go to plan. The whole ledger is rebuilt from
    /// these, so correcting one after the fact settles up correctly.
    var records: [TrashRecord] = []

    /// Derived from `records`. Written out so the file reads honestly on its
    /// own, but recomputed on load rather than trusted.
    var balances: [String: Double] = [:]

    /// A turn is two collections, so half a week is the unit of credit.
    static let half = 0.5
    private static let epsilon = 0.0001

    /// How far back a rebuild will walk. Bounds the work when swaps are old.
    private static let historyCap = 52

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
        var rota = Store.document.trashRota
        rota.balances = rota.ledger(covering: 0...0).balances
        return rota
    }

    func save() {
        var copy = self
        copy.balances = copy.ledger(covering: 0...0).balances
        Store.mutate { $0.trashRota = copy }
    }

    /// Tolerant of a document written before records and balances existed,
    /// and of the older `swaps` key whose frozen `dueWas` is now ignored.
    enum CodingKeys: String, CodingKey {
        case people, me, anchorMonday, anchorIndex, records, swaps, balances
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
        balances = value(.balances, [:])

        let current: [TrashRecord] = value(.records, [])
        records = current.isEmpty ? value(.swaps, []) : current
    }

    /// Spelled out because `swaps` is a read-only fallback with no property
    /// behind it, which leaves nothing for the compiler to synthesise.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(people, forKey: .people)
        try c.encode(me, forKey: .me)
        try c.encode(anchorMonday, forKey: .anchorMonday)
        try c.encode(anchorIndex, forKey: .anchorIndex)
        try c.encode(records, forKey: .records)
        try c.encode(balances, forKey: .balances)
    }

    // MARK: The plain rotation

    var currentWeek: Int { weekIndex(of: Date()) }

    func weekIndex(of date: Date) -> Int {
        let days = Self.gregorian.dateComponents(
            [.day], from: anchorMonday, to: Self.mondayOf(date)
        ).day ?? 0
        return Int((Double(days) / 7).rounded())
    }

    func monday(forWeek week: Int) -> Date {
        Self.gregorian.date(
            byAdding: .day, value: 7 * (week - currentWeek), to: Self.mondayOf(Date())
        ) ?? Self.mondayOf(Date())
    }

    /// Whose turn it is before any credit is taken into account.
    private func basePerson(_ week: Int) -> String {
        guard !people.isEmpty else { return "—" }
        let n = people.count
        return people[((anchorIndex + week) % n + n) % n]
    }

    // MARK: The ledger

    struct Ledger {
        var assignee: [Int: String] = [:]
        var balances: [String: Double] = [:]
    }

    /// Replays the weeks in order, settling up as it goes.
    ///
    /// Who was due for a week is decided here, during the replay, and a
    /// record only moves anything when it names somebody else. A record that
    /// agrees with the rotation is worth nothing, however the phase has been
    /// set since. Standing in moves half a turn from the person who was due
    /// to the person who did it. When the rotation then reaches somebody a
    /// whole turn in credit, it skips them and hands the week to whoever is
    /// furthest in debt, cancelling one turn on each side.
    func ledger(covering span: ClosedRange<Int>) -> Ledger {
        guard !people.isEmpty else { return Ledger() }

        let now = currentWeek
        let earliest = records.map { weekIndex(of: $0.date) }.min()
        let first = max(min(earliest ?? now, now + min(span.lowerBound, 0)), now - Self.historyCap)
        let last = now + max(span.upperBound, 0)
        guard first <= last else { return Ledger() }

        let byWeek = Dictionary(grouping: records) { weekIndex(of: $0.date) }
        var ledger = Ledger()

        for week in first...last {
            let base = basePerson(week)
            var who = base

            if (ledger.balances[base] ?? 0) >= 1 - Self.epsilon {
                ledger.balances[base, default: 0] -= 1

                // Furthest into debt wins the week; ties go to rota order.
                let owing = people.filter {
                    $0 != base && (ledger.balances[$0] ?? 0) <= -Self.epsilon
                }
                if let debtor = owing.min(by: {
                    (ledger.balances[$0] ?? 0) < (ledger.balances[$1] ?? 0)
                }) {
                    ledger.balances[debtor, default: 0] += 1
                    who = debtor
                } else {
                    who = basePerson(week + 1)
                }
            }

            ledger.assignee[week] = who

            // Records land after the week is assigned: they settle at the
            // next turn boundary, not the one they happened in. Whoever the
            // week turned out to belong to is the person who was due, so a
            // record naming them moves nothing.
            for record in byWeek[week] ?? [] where record.didIt != who {
                ledger.balances[record.didIt, default: 0] += Self.half
                ledger.balances[who, default: 0] -= Self.half
            }
        }

        ledger.balances = ledger.balances.filter { abs($0.value) > Self.epsilon }
        return ledger
    }

    /// Live balances, derived rather than read back from the stored snapshot.
    var currentBalances: [String: Double] {
        ledger(covering: 0...0).balances
    }

    func balance(for name: String) -> Double {
        currentBalances[name] ?? 0
    }

    func person(weeksAhead: Int = 0) -> String {
        guard !people.isEmpty else { return "—" }
        let week = currentWeek + weeksAhead
        let span = min(weeksAhead, 0)...max(weeksAhead, 0)
        return ledger(covering: span).assignee[week] ?? basePerson(week)
    }

    var thisWeek: String { person() }
    var lastWeek: String { person(weeksAhead: -1) }
    var nextWeek: String { person(weeksAhead: 1) }

    var isMyWeek: Bool {
        guard people.indices.contains(me) else { return false }
        return thisWeek == people[me]
    }

    // MARK: Phase

    /// Re-phases so `name` holds the week `weeksAhead` from now, rather than
    /// inferring the order from the order the names were typed in.
    mutating func setPerson(_ name: String, weeksAhead: Int) {
        guard !people.isEmpty, let index = people.firstIndex(of: name) else { return }
        let n = people.count
        anchorMonday = Self.mondayOf(Date())
        anchorIndex = ((index - weeksAhead) % n + n) % n
        save()
    }

    mutating func setCurrent(to index: Int) {
        guard people.indices.contains(index) else { return }
        setPerson(people[index], weeksAhead: 0)
    }

    /// Pins the anchor to whoever currently holds the base turn, so that
    /// changing the shape of the list does not shuffle everyone along.
    private mutating func rephase(onto name: String?) {
        anchorMonday = Self.mondayOf(Date())
        anchorIndex = name.flatMap { people.firstIndex(of: $0) } ?? 0
    }

    mutating func addPerson(_ name: String) {
        let keep = basePerson(currentWeek)
        people.append(name)
        rephase(onto: keep)
        save()
    }

    mutating func removePerson(at index: Int) {
        guard people.count > 1, people.indices.contains(index) else { return }

        let removed = people[index]
        let keep = basePerson(currentWeek)
        let next = basePerson(currentWeek + 1)

        people.remove(at: index)
        if index == me {
            me = 0
        } else if index < me {
            me -= 1
        }

        rephase(onto: keep == removed ? next : keep)
        save()
    }

    // MARK: Corrections

    /// The most recent collections, newest first, each with who was due.
    ///
    /// One replay answers the whole list, so every row reads its due person
    /// from the same settled schedule the card shows.
    func recentCollections(limit: Int = 4) -> [TrashCollection] {
        let cal = Self.gregorian
        let today = cal.startOfDay(for: Date())
        let span = -(limit + 2)...0
        let ledger = self.ledger(covering: span)

        var out: [TrashCollection] = []
        var week = currentWeek

        while out.count < limit && week > currentWeek + span.lowerBound {
            let monday = self.monday(forWeek: week)
            let thursday = cal.date(byAdding: .day, value: 3, to: monday) ?? monday
            let due = ledger.assignee[week] ?? person(weeksAhead: week - currentWeek)

            for day in [thursday, monday] where day <= today && out.count < limit {
                out.append(
                    TrashCollection(date: day, due: due, didIt: whoDid(on: day) ?? due)
                )
            }
            week -= 1
        }
        return out
    }

    func whoDid(on day: Date) -> String? {
        let cal = Self.gregorian
        return records.first { cal.isDate($0.date, inSameDayAs: day) }?.didIt
    }

    /// Records who actually did a collection. Naming the person who was due
    /// stores nothing, so following the schedule needs no logging and leaves
    /// no record to be reinterpreted if the phase moves later.
    mutating func record(_ who: String, for day: Date, due: String) {
        let cal = Self.gregorian
        let date = cal.startOfDay(for: day)

        records.removeAll { cal.isDate($0.date, inSameDayAs: date) }
        if who != due {
            records.append(TrashRecord(date: date, didIt: who))
            records.sort { $0.date < $1.date }
        }
        save()
    }

    /// "½ owed", "1½ owing", or nothing at all when square.
    static func balanceLabel(_ value: Double) -> String? {
        guard abs(value) > epsilon else { return nil }

        let size = abs(value)
        let wholes = Int(size)
        let hasHalf = size - Double(wholes) > epsilon

        var amount = ""
        if wholes > 0 { amount += "\(wholes)" }
        if hasHalf { amount += "½" }

        return "\(amount) \(value > 0 ? "owed" : "owing")"
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
                        collectionsPanel
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

    /// Says who is on which week outright, rather than leaving the phase to
    /// be inferred from the order the names were typed in.
    private var turnPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("whose turn")
                .font(.system(size: 9, weight: .black))
                .tracking(1.6)
                .foregroundStyle(Palette.bone.opacity(0.3))

            turnRow("last week", offset: -1, person: rota.lastWeek)
            turnRow("this week", offset: 0, person: rota.thisWeek)
            turnRow("next week", offset: 1, person: rota.nextWeek)

            Text("setting one of these re-phases the whole rotation")
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

    /// The last four collections, each already showing the person who was
    /// due, so a correction is one tap and an ordinary week needs none.
    private var collectionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("who took them out")
                .font(.system(size: 9, weight: .black))
                .tracking(1.6)
                .foregroundStyle(Palette.bone.opacity(0.3))

            ForEach(rota.recentCollections()) { slot in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.dayLabel.string(from: slot.date).lowercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.bone.opacity(0.75))

                        if slot.isCorrected {
                            Text("\(slot.due.lowercased()) was due")
                                .font(.system(size: 9, weight: .black))
                                .tracking(1.1)
                                .foregroundStyle(Palette.redHot.opacity(0.65))
                        }
                    }
                    .frame(width: 92, alignment: .leading)

                    PersonMenu(people: rota.people, selection: slot.didIt) { name in
                        haptics.soft()
                        rota.record(name, for: slot.date, due: slot.due)
                        Task { await TrashReminder.reschedule(rota) }
                    }

                    Spacer()
                }
            }

            Text("a turn is two collections, so standing in for one is half a turn")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.bone.opacity(0.28))
                .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackdrop(cornerRadius: 28, tint: Palette.bone.opacity(0.06))
    }

    private static let dayLabel: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f
    }()

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

                    if let balance = TrashRota.balanceLabel(rota.balance(for: name)) {
                        Text(balance)
                            .font(.system(size: 9, weight: .black))
                            .tracking(1.1)
                            .foregroundStyle(
                                rota.balance(for: name) > 0
                                ? Palette.bone.opacity(0.45)
                                : Palette.redHot.opacity(0.75)
                            )
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Palette.steel))
                    }

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
