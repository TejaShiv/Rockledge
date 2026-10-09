import Foundation
import Testing
@testable import anynameyoulike

/// Folding the two old reminders into one. Getting this wrong silently loses
/// a setting the user chose, which they would only notice by being woken at
/// the wrong time or not at all.
///
/// Serialised: these all work on the one shared UserDefaults.
@Suite(.serialized)
struct NightlyReminderTests {

    private static let keys = [
        "nightlyReminderOn", "nightlyReminderHour", "nightlyReminderMinute",
        "nightlyReminderMigratedV1",
        "reminderEnabled", "reminderHour", "reminderMinute",
        "groceryReminderOn", "groceryReminderHour", "groceryReminderMinute",
    ]

    /// Puts the old world in place and clears anything from a previous test.
    private func start(old settings: [String: Any]) {
        let defaults = UserDefaults.standard
        for key in Self.keys { defaults.removeObject(forKey: key) }
        for (key, value) in settings { defaults.set(value, forKey: key) }
    }

    private func clear() {
        for key in Self.keys { UserDefaults.standard.removeObject(forKey: key) }
    }

    // MARK: Carrying settings over

    @Test func keepsAChosenStepTime() {
        start(old: ["reminderEnabled": true, "reminderHour": 21, "reminderMinute": 15])
        defer { clear() }

        #expect(NightlyReminder.isEnabled)
        #expect(NightlyReminder.hour == 21)
        #expect(NightlyReminder.minute == 15)
    }

    @Test func keepsAChosenGroceryTime() {
        start(old: ["groceryReminderOn": true, "groceryReminderHour": 19,
                    "groceryReminderMinute": 45])
        defer { clear() }

        #expect(NightlyReminder.hour == 19)
        #expect(NightlyReminder.minute == 45)
    }

    /// This fires at the end of the day, so the earlier of two chosen times
    /// would go off before the day is done.
    @Test func takesTheLaterOfTwoChosenTimes() {
        start(old: [
            "reminderHour": 20, "reminderMinute": 30,
            "groceryReminderHour": 23, "groceryReminderMinute": 5,
        ])
        defer { clear() }

        #expect(NightlyReminder.hour == 23)
        #expect(NightlyReminder.minute == 5)
    }

    @Test func landsOnHalfTenWhenNothingWasChosen() {
        start(old: [:])
        defer { clear() }

        #expect(NightlyReminder.hour == 22)
        #expect(NightlyReminder.minute == 30)
    }

    // MARK: Carrying the toggles over

    @Test func staysOnIfEitherWasOn() {
        start(old: ["reminderEnabled": true, "groceryReminderOn": false])
        defer { clear() }
        #expect(NightlyReminder.isEnabled)

        start(old: ["reminderEnabled": false, "groceryReminderOn": true])
        defer { clear() }
        #expect(NightlyReminder.isEnabled)
    }

    @Test func staysOffOnlyIfBothWereOff() {
        start(old: ["reminderEnabled": false, "groceryReminderOn": false])
        defer { clear() }

        #expect(!NightlyReminder.isEnabled)
    }

    /// Groceries defaulted to on, so somebody who never touched either should
    /// still get the nightly nudge.
    @Test func isOnForSomebodyWhoNeverChangedAnything() {
        start(old: [:])
        defer { clear() }

        #expect(NightlyReminder.isEnabled)
    }

    // MARK: Afterwards

    @Test func clearsTheOldKeysSoThereIsOneSourceOfTruth() {
        start(old: ["reminderEnabled": true, "reminderHour": 21,
                    "groceryReminderOn": true, "groceryReminderHour": 22])
        defer { clear() }

        _ = NightlyReminder.isEnabled

        let defaults = UserDefaults.standard
        #expect(defaults.object(forKey: "reminderEnabled") == nil)
        #expect(defaults.object(forKey: "reminderHour") == nil)
        #expect(defaults.object(forKey: "groceryReminderOn") == nil)
        #expect(defaults.object(forKey: "groceryReminderHour") == nil)
    }

    @Test func onlyMigratesOnce() {
        start(old: ["reminderEnabled": true, "reminderHour": 21, "reminderMinute": 15])
        defer { clear() }

        _ = NightlyReminder.hour              // migrates
        NightlyReminder.hour = 6              // then the user picks something
        UserDefaults.standard.set(23, forKey: "reminderHour")   // a stale old key

        #expect(NightlyReminder.hour == 6)    // not clobbered by a second pass
    }

    @Test func aLaterChoiceWins() {
        start(old: ["groceryReminderHour": 19, "groceryReminderMinute": 45])
        defer { clear() }

        #expect(NightlyReminder.hour == 19)

        NightlyReminder.hour = 21
        NightlyReminder.minute = 0

        #expect(NightlyReminder.hour == 21)
        #expect(NightlyReminder.minute == 0)
    }
}
