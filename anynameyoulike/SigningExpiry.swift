import Foundation
import SwiftUI
import UserNotifications

// MARK: - Reading the profile

/// When this build stops launching.
///
/// A free Personal Team signs for a week at a time, and the app simply dies
/// when the profile lapses — SIGKILL before any code runs, so there is no
/// chance to warn from inside. The warning has to come beforehand, which
/// means knowing the real expiry date.
///
/// Read from the embedded profile rather than inferred from a rebuild date:
/// Xcode reuses an unexpired profile, so a rebuild often does not move the
/// expiry at all and counting from it would promise time that is not there.
nonisolated enum Signing {

    struct Profile: Equatable {
        /// From the profile's ExpirationDate.
        var expiresAt: Date
        /// When this copy landed on the phone, from the executable's own
        /// modification date. Nil if it cannot be read.
        var installedAt: Date?
    }

    /// Nil in the Simulator, which has no profile, and the feature then has
    /// nothing to say and stays out of the way.
    static func profile(in bundle: Bundle = .main) -> Profile? {
        guard let expiresAt = expiryDate(in: bundle) else { return nil }
        return Profile(expiresAt: expiresAt, installedAt: installDate(in: bundle))
    }

    /// The profile is CMS-signed, with an XML plist in the middle of it. The
    /// plist is cut out by its own delimiters rather than by decoding the
    /// signature, which needs no crypto and does not care about the envelope.
    static func expiryDate(in bundle: Bundle = .main) -> Date? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url)
        else { return nil }

        return expiryDate(fromProfile: data)
    }

    /// Split out so it can be exercised on a fixture rather than on whatever
    /// happens to be signing the test host.
    static func expiryDate(fromProfile data: Data) -> Date? {
        guard let opening = data.range(of: Data("<?xml".utf8)),
              let closing = data.range(of: Data("</plist>".utf8), in: opening.upperBound..<data.endIndex)
        else { return nil }

        let plist = data[opening.lowerBound ..< closing.upperBound]

        guard let parsed = try? PropertyListSerialization.propertyList(
                from: plist, options: [], format: nil
              ) as? [String: Any]
        else { return nil }

        return parsed["ExpirationDate"] as? Date
    }

    private static func installDate(in bundle: Bundle) -> Date? {
        guard let executable = bundle.executableURL else { return nil }
        return try? executable
            .resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }

    // MARK: How much time is left

    enum Urgency {
        case comfortable        // more than two days
        case soon               // under two days
        case urgent             // under a day
        case expired

        /// Only ever read while drawing, which is also the only place
        /// Palette can be reached from.
        @MainActor
        var tint: Color {
            switch self {
            case .comfortable: return .teal
            case .soon: return .orange
            case .urgent, .expired: return Palette.redHot
            }
        }

        var symbol: String {
            switch self {
            case .comfortable: return "checkmark.seal"
            case .soon: return "clock"
            case .urgent: return "exclamationmark.circle"
            case .expired: return "xmark.octagon"
            }
        }
    }

    static func urgency(remaining: TimeInterval) -> Urgency {
        if remaining <= 0 { return .expired }
        if remaining < 24 * 3600 { return .urgent }
        if remaining < 48 * 3600 { return .soon }
        return .comfortable
    }

    /// "5 days until rebuild", "Rebuild within 3 hours".
    ///
    /// Days are rounded down, so the headline never promises more time than
    /// there is.
    static func headline(remaining: TimeInterval) -> String {
        guard remaining > 0 else { return "Rebuild needed" }

        if remaining >= 48 * 3600 {
            return "\(Int(remaining / 86_400)) days until rebuild"
        }
        if remaining >= 24 * 3600 {
            return "1 day until rebuild"
        }
        if remaining >= 3600 {
            return "Rebuild within \(Int(remaining / 3600)) hours"
        }
        return "Rebuild within the hour"
    }

    /// "Works until Sat, Nov 1, 7:42 PM. Installed Oct 26, 7:42 PM."
    static func detail(for profile: Profile) -> String {
        var text = "Works until \(until.string(from: profile.expiresAt))."
        if let installedAt = profile.installedAt {
            text += " Installed \(installed.string(from: installedAt))."
        }
        return text
    }

    private static let until: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d, h:mm a"
        return f
    }()

    private static let installed: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    private static let spoken: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE 'at' h:mm a"
        return f
    }()

    // MARK: Reminders

    private static let identifiers = ["signingRebuild-24h", "signingRebuild-2h"]

    /// What each reminder says, in the order they are scheduled.
    private static func copy(for lead: TimeInterval, expiresAt: Date) -> (String, String) {
        let when = spoken.string(from: expiresAt)

        if lead > 2 * 3600 {
            return (
                "Tally needs a rebuild soon",
                "It stops opening \(when). Plug into your Mac and press Run in Xcode when you have a minute."
            )
        }
        return (
            "Last call to rebuild Tally",
            "It stops opening \(when). A quick rebuild now keeps everything running."
        )
    }

    /// Nothing overnight: a reminder landing between 10pm and 8am is moved
    /// back to 9pm, so it is always earlier than it would have been rather
    /// than later.
    static func civilised(_ date: Date, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: date)
        guard hour >= 22 || hour < 8 else { return date }

        // Before 8am belongs to the previous evening; after 10pm to this one.
        let evening = hour < 8
            ? calendar.date(byAdding: .day, value: -1, to: date) ?? date
            : date

        return calendar.date(bySettingHour: 21, minute: 0, second: 0, of: evening) ?? date
    }

    /// The times two reminders should actually fire, in order.
    ///
    /// Anything already past is dropped, and a pair that has been nudged onto
    /// the same evening collapses to one, so the same minute never fires
    /// twice.
    static func reminderTimes(expiresAt: Date,
                              now: Date = Date(),
                              calendar: Calendar = .current) -> [(lead: TimeInterval, fire: Date)] {
        var times: [(lead: TimeInterval, fire: Date)] = []

        for lead in [24 * 3600.0, 2 * 3600.0] {
            let fire = civilised(expiresAt.addingTimeInterval(-lead), calendar: calendar)
            guard fire > now else { continue }
            guard !times.contains(where: { $0.fire == fire }) else { continue }
            times.append((lead, fire))
        }
        return times
    }

    /// Clears the previous pair and lays down a fresh one. Called on launch
    /// and on every return to the foreground, since the profile can change
    /// underneath a running install.
    static func scheduleReminders(now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        guard let profile = profile() else { return }

        let times = reminderTimes(expiresAt: profile.expiresAt, now: now)
        guard !times.isEmpty else { return }
        guard await permission() else { return }

        for (index, slot) in times.enumerated() {
            let (title, body) = copy(for: slot.lead, expiresAt: profile.expiresAt)

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.interruptionLevel = .timeSensitive

            let parts = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: slot.fire
            )

            try? await center.add(
                UNNotificationRequest(
                    identifier: identifiers[index],
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                )
            )
        }
    }

    private static func permission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge]))
                ?? false
        case .denied:
            return false
        default:
            return true
        }
    }
}

// MARK: - The strip

/// A slim line above everything else, saying how long this build has left.
///
/// Shows nothing at all without a profile, so the Simulator is unaffected.
struct SigningStrip: View {
    private let profile = Signing.profile()

    var body: some View {
        if let profile {
            // Re-reads the clock every minute, which is all the precision a
            // countdown in days and hours needs.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                strip(for: profile, at: context.date)
            }
        }
    }

    private func strip(for profile: Signing.Profile, at now: Date) -> some View {
        let remaining = profile.expiresAt.timeIntervalSince(now)
        let urgency = Signing.urgency(remaining: remaining)

        return HStack(spacing: 10) {
            Image(systemName: urgency.symbol)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(urgency.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(Signing.headline(remaining: remaining))
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(urgency.tint)

                Text(Signing.detail(for: profile))
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(Palette.bone.opacity(0.35))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(urgency.tint.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(urgency.tint.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
