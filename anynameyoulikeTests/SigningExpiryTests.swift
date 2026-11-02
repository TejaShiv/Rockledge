import Foundation
import Testing
@testable import anynameyoulike

/// Reading the expiry, and deciding when to warn about it.
///
/// The parsing is exercised on a fixture rather than on whatever is signing
/// the test host, which in the Simulator is nothing at all.
struct SigningExpiryTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func at(_ year: Int, _ month: Int, _ day: Int,
                    _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    // MARK: Pulling the plist out of the profile

    /// A profile is CMS-signed, so the plist sits in the middle of bytes that
    /// are not XML at all.
    private func fixture(expiring: String) -> Data {
        var data = Data([0x30, 0x82, 0x0A, 0xBC, 0x00, 0xFF])   // DER-ish noise
        data.append(Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Name</key><string>iOS Team Provisioning Profile</string>
        <key>CreationDate</key><date>2026-11-02T06:03:03Z</date>
        <key>ExpirationDate</key><date>\(expiring)</date>
        </dict></plist>
        """.utf8))
        data.append(Data([0x00, 0x01, 0x02, 0xAA]))             // trailing signature
        return data
    }

    @Test func readsTheExpiryOutOfASignedProfile() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let expected = utc.date(from: DateComponents(
            year: 2026, month: 11, day: 9, hour: 6, minute: 3, second: 3
        ))!

        let found = Signing.expiryDate(fromProfile: fixture(expiring: "2026-11-09T06:03:03Z"))

        #expect(found == expected)
    }

    @Test func survivesBytesEitherSideOfThePlist() throws {
        let found = try #require(
            Signing.expiryDate(fromProfile: fixture(expiring: "2027-01-01T00:00:00Z"))
        )
        let parts = calendar.dateComponents([.year], from: found)

        #expect(parts.year == 2026 || parts.year == 2027)   // whichever side of UTC
    }

    @Test func refusesSomethingThatIsNotAProfile() {
        #expect(Signing.expiryDate(fromProfile: Data()) == nil)
        #expect(Signing.expiryDate(fromProfile: Data("not a profile".utf8)) == nil)
        // An opening tag with no closing one is not a plist.
        #expect(Signing.expiryDate(fromProfile: Data("<?xml version=\"1.0\"?>".utf8)) == nil)
    }

    @Test func refusesAPlistWithoutAnExpiry() {
        var data = Data([0x30, 0x82])
        data.append(Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Name</key><string>x</string></dict></plist>
        """.utf8))

        #expect(Signing.expiryDate(fromProfile: data) == nil)
    }

    /// The Simulator has no profile, and the whole feature has to vanish.
    @Test func thereIsNoProfileInTheSimulator() {
        #expect(Signing.profile(in: .main) == nil)
    }

    // MARK: How it reads

    @Test func countsDownInDaysThenHours() {
        #expect(Signing.headline(remaining: 5 * 86_400) == "5 days until rebuild")
        #expect(Signing.headline(remaining: 2 * 86_400) == "2 days until rebuild")
        #expect(Signing.headline(remaining: 36 * 3600) == "1 day until rebuild")
        #expect(Signing.headline(remaining: 3 * 3600) == "Rebuild within 3 hours")
        #expect(Signing.headline(remaining: 600) == "Rebuild within the hour")
        #expect(Signing.headline(remaining: 0) == "Rebuild needed")
        #expect(Signing.headline(remaining: -500) == "Rebuild needed")
    }

    /// Rounded down, so it never promises time that is not there.
    @Test func neverRoundsTheCountdownUp() {
        #expect(Signing.headline(remaining: 5.9 * 86_400) == "5 days until rebuild")
        #expect(Signing.headline(remaining: 3.99 * 3600) == "Rebuild within 3 hours")
    }

    @Test func getsLouderAsItRunsOut() {
        #expect(Signing.urgency(remaining: 5 * 86_400) == .comfortable)
        #expect(Signing.urgency(remaining: 47 * 3600) == .soon)
        #expect(Signing.urgency(remaining: 23 * 3600) == .urgent)
        #expect(Signing.urgency(remaining: 0) == .expired)
        #expect(Signing.urgency(remaining: -1) == .expired)
    }

    @Test func sayWhenItStopsAndWhenItLanded() {
        let profile = Signing.Profile(
            expiresAt: at(2026, 11, 7, 19, 42),
            installedAt: at(2026, 11, 1, 19, 42)
        )

        let detail = Signing.detail(for: profile)

        #expect(detail.hasPrefix("Works until "))
        #expect(detail.contains("7:42 PM"))
        #expect(detail.contains("Installed "))
    }

    @Test func leavesOutTheInstallDateWhenItCannotBeRead() {
        let detail = Signing.detail(
            for: Signing.Profile(expiresAt: at(2026, 11, 7, 19, 42), installedAt: nil)
        )

        #expect(!detail.contains("Installed"))
    }

    // MARK: Not in the middle of the night

    @Test func leavesACivilisedTimeAlone() {
        for hour in 8...21 {
            let time = at(2026, 11, 3, hour)
            #expect(Signing.civilised(time, calendar: calendar) == time)
        }
    }

    @Test func pullsALateNightReminderBackToNine() {
        #expect(Signing.civilised(at(2026, 11, 3, 23), calendar: calendar)
                == at(2026, 11, 3, 21))
        #expect(Signing.civilised(at(2026, 11, 3, 22), calendar: calendar)
                == at(2026, 11, 3, 21))
    }

    /// Small hours belong to the evening before, not the one coming.
    @Test func pullsAnEarlyMorningReminderBackToTheNightBefore() {
        #expect(Signing.civilised(at(2026, 11, 4, 2), calendar: calendar)
                == at(2026, 11, 3, 21))
        #expect(Signing.civilised(at(2026, 11, 4, 7, 59), calendar: calendar)
                == at(2026, 11, 3, 21))
    }

    @Test func alwaysMovesAReminderEarlierNeverLater() {
        for hour in 0...23 {
            let time = at(2026, 11, 4, hour)
            #expect(Signing.civilised(time, calendar: calendar) <= time)
        }
    }

    // MARK: Which reminders actually get laid down

    @Test func schedulesOneADayOutAndOneTwoHoursOut() {
        let expiry = at(2026, 11, 7, 18)        // both land in daylight
        let now = at(2026, 11, 1, 12)

        let times = Signing.reminderTimes(expiresAt: expiry, now: now, calendar: calendar)

        #expect(times.count == 2)
        #expect(times[0].fire == at(2026, 11, 6, 18))
        #expect(times[1].fire == at(2026, 11, 7, 16))
    }

    @Test func dropsAReminderWhoseMomentHasPassed() {
        let expiry = at(2026, 11, 7, 18)
        let now = at(2026, 11, 7, 12)           // the day-out one is long gone

        let times = Signing.reminderTimes(expiresAt: expiry, now: now, calendar: calendar)

        #expect(times.count == 1)
        #expect(times[0].lead == 2 * 3600)
    }

    @Test func schedulesNothingOnceItHasExpired() {
        let expiry = at(2026, 11, 7, 18)

        #expect(Signing.reminderTimes(
            expiresAt: expiry, now: at(2026, 11, 8, 9), calendar: calendar
        ).isEmpty)
    }

    /// An expiry in the small hours drags both reminders onto the same
    /// evening, and the same minute must not fire twice.
    @Test func collapsesTwoRemindersThatLandTogether() {
        let expiry = at(2026, 11, 7, 3)         // 3am
        let now = at(2026, 11, 1, 12)

        let times = Signing.reminderTimes(expiresAt: expiry, now: now, calendar: calendar)

        // 24h out is 3am on the 6th -> 9pm on the 5th.
        // 2h out is 1am on the 7th -> 9pm on the 6th. Different evenings.
        #expect(times.count == 2)
        #expect(times[0].fire == at(2026, 11, 5, 21))
        #expect(times[1].fire == at(2026, 11, 6, 21))
        #expect(Set(times.map(\.fire)).count == times.count)
    }

    @Test func neverSchedulesTheSameMinuteTwice() {
        // Walk a week of expiry times and check no pair ever collides.
        for hour in 0...23 {
            let expiry = at(2026, 11, 7, hour)
            let times = Signing.reminderTimes(
                expiresAt: expiry, now: at(2026, 10, 1, 12), calendar: calendar
            )
            #expect(Set(times.map(\.fire)).count == times.count)
        }
    }

    @Test func everyReminderLandsInWakingHours() {
        for hour in 0...23 {
            let expiry = at(2026, 11, 7, hour)
            let times = Signing.reminderTimes(
                expiresAt: expiry, now: at(2026, 10, 1, 12), calendar: calendar
            )

            for slot in times {
                let fired = calendar.component(.hour, from: slot.fire)
                #expect(fired >= 8 && fired < 22)
            }
        }
    }
}
