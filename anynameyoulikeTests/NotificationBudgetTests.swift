import Foundation
import Testing
@testable import anynameyoulike

/// Counting what iOS is holding.
///
/// Pure throughout: the census is built from a list of identifiers, so none
/// of this touches the notification centre the app itself is scheduling
/// against while the tests run.
struct NotificationBudgetTests {

    // MARK: Which module an identifier belongs to

    @Test func recognisesEveryModuleThatSchedules() {
        #expect(NotificationModules.label(for: "canvas-991-2d") == "canvas")
        #expect(NotificationModules.label(for: "canvas-991-1d") == "canvas")
        #expect(NotificationModules.label(for: "trashNight-1793600000") == "trash")
        #expect(NotificationModules.label(for: "signingRebuild-24h") == "signing")
        #expect(NotificationModules.label(for: "signingRebuild-2h") == "signing")
        #expect(NotificationModules.label(for: "nightlyReminder") == "nightly")
    }

    /// The test reminder is its own line: it is not part of any budget and
    /// seeing it counted as the real nightly one would be misleading.
    @Test func keepsTheTestReminderSeparate() {
        #expect(NotificationModules.label(for: "nightlyTest-ABC-123") == "nightly test")
    }

    /// Anything unrecognised has to show up somewhere. A notification that
    /// goes uncounted is the exact failure this is built to catch.
    @Test func neverDropsAnIdentifierItDoesNotKnow() {
        #expect(NotificationModules.label(for: "something-new") == "other")
        #expect(NotificationModules.label(for: "") == "other")
    }

    // MARK: The count

    @Test func addsUpAndBreaksDown() {
        let census = NotificationModules.census(of: [
            "canvas-1-2d", "canvas-1-1d", "canvas-2-2d",
            "trashNight-100", "trashNight-200",
            "signingRebuild-24h",
            "nightlyReminder",
        ])

        #expect(census.total == 7)
        #expect(census.modules.map(\.name) == ["canvas", "trash", "nightly", "signing"])
        #expect(census.modules.first?.count == 3)
    }

    /// Biggest first, so whatever needs trimming is at the top. Equal counts
    /// sort by name, or the list would reshuffle between readings.
    @Test func ordersByWeightThenSteadily() {
        let census = NotificationModules.census(of: [
            "nightlyReminder", "trashNight-1", "signingRebuild-2h",
        ])

        #expect(census.modules.map(\.name) == ["nightly", "signing", "trash"])
        #expect(census.modules.allSatisfy { $0.count == 1 })
    }

    @Test func copesWithNothingScheduled() {
        let census = NotificationModules.census(of: [])

        #expect(census.total == 0)
        #expect(census.modules.isEmpty)
        #expect(census.pressure == .fine)
        #expect(census.line == "notifications 0/64")
    }

    // MARK: How loudly it reads

    /// Including 55, which is everything the app can schedule at once.
    @Test func staysQuietThroughTheBusiestNormalWeek() {
        for total in [0, 20, 49, 50, 55] {
            #expect(census(total).pressure == .fine, "\(total) should be quiet")
        }
    }

    @Test func warnsFromFiftySixToFiftySeven() {
        for total in [56, 57] {
            #expect(census(total).pressure == .tight, "\(total) should warn")
        }
    }

    /// Above 57 is the signal that Canvas's cap of 40 is too generous.
    @Test func shoutsAboveFiftySeven() {
        for total in [58, 63, 64, 70] {
            #expect(census(total).pressure == .critical, "\(total) should shout")
        }
    }

    @Test func knowsTheRealLimit() {
        #expect(NotificationCensus.limit == 64)
    }

    // MARK: The console line

    @Test func readsAsOneLineInTheConsole() {
        let census = NotificationModules.census(of: [
            "canvas-1-2d", "canvas-2-2d", "signingRebuild-24h",
        ])

        #expect(census.line == "notifications 3/64 — canvas 2, signing 1")
    }

    /// The budget this exists to police: forty Canvas plus everything else
    /// has to leave the signing pair room inside sixty-four.
    @Test func theWholeAppAtFullStretchStillFits() {
        var identifiers = (0..<40).map { "canvas-\($0)-2d" }
        identifiers += (0..<12).map { "trashNight-\($0)" }
        identifiers += ["signingRebuild-24h", "signingRebuild-2h", "nightlyReminder"]

        let census = NotificationModules.census(of: identifiers)

        #expect(census.total == 55)
        #expect(census.total < NotificationCensus.limit)
        // Healthy, not a warning: this is as loaded as the app can get on
        // its own, so orange here would mean orange most weeks.
        #expect(census.pressure == .fine)
    }

    private func census(_ total: Int) -> NotificationCensus {
        NotificationModules.census(of: (0..<total).map { "canvas-\($0)-2d" })
    }
}
