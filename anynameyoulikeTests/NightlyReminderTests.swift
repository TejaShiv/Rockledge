import Foundation
import Testing
@testable import anynameyoulike

/// Folding the two old reminders into one. Getting this wrong silently loses
/// a setting the user chose, which they would only notice by being woken at
/// the wrong time or not at all.
///
/// Checked through the pure function rather than UserDefaults: these run
/// inside the app, which migrates on its own at launch and would race them.
struct NightlyReminderTests {

    // MARK: Carrying times over

    @Test func keepsAChosenStepTime() {
        let carried = NightlyReminder.carriedOver(from: [
            "reminderEnabled": true, "reminderHour": 21, "reminderMinute": 15,
        ])

        #expect(carried.enabled)
        #expect(carried.hour == 21)
        #expect(carried.minute == 15)
    }

    @Test func keepsAChosenGroceryTime() {
        let carried = NightlyReminder.carriedOver(from: [
            "groceryReminderOn": true, "groceryReminderHour": 19,
            "groceryReminderMinute": 45,
        ])

        #expect(carried.hour == 19)
        #expect(carried.minute == 45)
    }

    /// This fires at the end of the day, so the earlier of two chosen times
    /// would go off before the day is done.
    @Test func takesTheLaterOfTwoChosenTimes() {
        let carried = NightlyReminder.carriedOver(from: [
            "reminderHour": 20, "reminderMinute": 30,
            "groceryReminderHour": 23, "groceryReminderMinute": 5,
        ])

        #expect(carried.hour == 23)
        #expect(carried.minute == 5)
    }

    /// Nothing chosen leaves the new default standing.
    @Test func noChosenTimeMeansNoTimeToCarry() {
        let carried = NightlyReminder.carriedOver(from: [:])

        #expect(carried.hour == nil)
        #expect(carried.minute == nil)
        #expect(NightlyReminder.defaultHour == 22)
        #expect(NightlyReminder.defaultMinute == 30)
    }

    @Test func aChosenHourWithNoMinuteIsOnTheHour() {
        let carried = NightlyReminder.carriedOver(from: ["reminderHour": 21])

        #expect(carried.hour == 21)
        #expect(carried.minute == 0)
    }

    // MARK: Carrying the toggles over

    @Test func staysOnIfEitherWasOn() {
        #expect(NightlyReminder.carriedOver(from: [
            "reminderEnabled": true, "groceryReminderOn": false,
        ]).enabled)

        #expect(NightlyReminder.carriedOver(from: [
            "reminderEnabled": false, "groceryReminderOn": true,
        ]).enabled)
    }

    @Test func staysOffOnlyIfBothWereOff() {
        let carried = NightlyReminder.carriedOver(from: [
            "reminderEnabled": false, "groceryReminderOn": false,
        ])

        #expect(!carried.enabled)
    }

    /// Groceries defaulted to on, so somebody who never touched either should
    /// still get the nightly nudge.
    @Test func isOnForSomebodyWhoNeverChangedAnything() {
        #expect(NightlyReminder.carriedOver(from: [:]).enabled)
    }

    /// Steps defaulted to off, so its absence must not turn the whole thing
    /// off for somebody who had groceries on.
    @Test func anAbsentStepToggleDoesNotOutvoteGroceries() {
        #expect(NightlyReminder.carriedOver(from: ["groceryReminderOn": true]).enabled)
        #expect(!NightlyReminder.carriedOver(from: ["groceryReminderOn": false]).enabled)
    }
}
