import Foundation
import Observation
import SwiftUI
import UserNotifications

// MARK: - What is actually pending

/// A count of the notifications iOS is really holding for this app.
///
/// iOS keeps 64 pending notifications per app and drops the rest **without
/// an error** — `add` succeeds, the request simply never arrives. Every
/// module here schedules against a budget that was estimated rather than
/// measured, so the first sign of an overflow would be a reminder that
/// quietly did not happen. This counts them for real instead.
nonisolated struct NotificationCensus: Equatable {

    /// Apple's cap. Not configurable, and not documented as an error.
    static let limit = 64

    struct Module: Equatable, Identifiable {
        var name: String
        var count: Int
        var id: String { name }
    }

    var total: Int
    /// Largest first, so the one to cut is at the top.
    var modules: [Module]
    var takenAt: Date

    enum Pressure {
        case fine           // under 56
        case tight          // 56 to 57
        case critical       // above 57

        @MainActor
        var tint: Color {
            switch self {
            case .fine: return Palette.bone.opacity(0.45)
            case .tight: return .orange
            case .critical: return Palette.redHot
            }
        }
    }

    /// Orange starts at 56, not 50.
    ///
    /// The app's structural maximum is 55 — forty Canvas, twelve trash, two
    /// signing, one nightly — so a band opening at 50 would have been orange
    /// through an ordinary busy week. A warning that is on during normal
    /// operation is not a warning. At 56 it can only mean something has been
    /// added that the budgets do not account for.
    var pressure: Pressure {
        if total > 57 { return .critical }
        if total >= 56 { return .tight }
        return .fine
    }

    /// One line, for the console.
    var line: String {
        let parts = modules.map { "\($0.name) \($0.count)" }.joined(separator: ", ")
        return "notifications \(total)/\(Self.limit)"
            + (parts.isEmpty ? "" : " — \(parts)")
    }
}

// MARK: - Reading the identifiers

/// Which module an identifier belongs to.
///
/// Derived from the prefixes the schedulers already use, so nothing had to
/// change to be counted. Anything unrecognised lands in "other" rather than
/// being dropped — an uncounted notification is exactly the thing this is
/// here to catch.
nonisolated enum NotificationModules {

    static func label(for identifier: String) -> String {
        if identifier.hasPrefix("canvas-") { return "canvas" }
        if identifier.hasPrefix("trashNight") { return "trash" }
        if identifier.hasPrefix("signingRebuild") { return "signing" }
        if identifier.hasPrefix("nightlyTest") { return "nightly test" }
        if identifier == "nightlyReminder" { return "nightly" }
        return "other"
    }

    /// Pure, so it can be exercised without the notification centre.
    static func census(of identifiers: [String],
                       takenAt: Date = Date()) -> NotificationCensus {
        var counts: [String: Int] = [:]
        for identifier in identifiers {
            counts[label(for: identifier), default: 0] += 1
        }

        let modules = counts
            .map { NotificationCensus.Module(name: $0.key, count: $0.value) }
            // Biggest first, then alphabetically so equal counts do not
            // shuffle between readings.
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }

        return NotificationCensus(
            total: identifiers.count, modules: modules, takenAt: takenAt
        )
    }
}

// MARK: - The ledger

/// Holds the latest count for the UI to read.
@Observable
final class NotificationLedger {

    private(set) var census: NotificationCensus?

    /// Called after every scheduling pass and on launch. Cheap: one call
    /// into the notification centre and a dictionary.
    func measure() async {
        let pending = await UNUserNotificationCenter.current()
            .pendingNotificationRequests()

        let taken = NotificationModules.census(of: pending.map(\.identifier))
        census = taken

        // Visible in the Xcode console, which is where this gets read while
        // the budgets are still guesses.
        print("[Tally] \(taken.line)")
    }
}
