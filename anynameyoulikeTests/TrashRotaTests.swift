import Foundation
import Testing
@testable import anynameyoulike

/// Covers the rotation and the turn pickers. Everything here builds a rota by
/// hand and reads it back through the pure accessors.
struct TrashRotaTests {

    /// A rota of `names` anchored to this Monday, so `people[0]` holds the
    /// current week.
    private func rota(_ names: [String]) -> TrashRota {
        var r = TrashRota()
        r.people = names
        r.anchorMonday = TrashRota.mondayOf(Date())
        r.anchorIndex = 0
        return r
    }

    /// The cycle as it reads from this week forward.
    private func cycle(_ r: TrashRota) -> [String] {
        (0..<r.people.count).map { r.person(weeksAhead: $0) }
    }

    // MARK: Rotation

    @Test func rotatesOnePersonPerWeek() {
        let r = rota(["A", "B", "C"])
        #expect(r.lastWeek == "C")
        #expect(r.thisWeek == "A")
        #expect(r.nextWeek == "B")
        #expect(r.person(weeksAhead: 3) == "A")
    }

    @Test func keepsCyclingPastTheEndOfTheList() {
        let r = rota(["A", "B", "C"])
        #expect((0..<7).map { r.person(weeksAhead: $0) }
                == ["A", "B", "C", "A", "B", "C", "A"])
    }

    // MARK: Setting a turn

    @Test func settingThisWeekLeavesTheRestOfTheCycleInOrder() {
        var r = rota(["A", "B", "C"])

        r.setPerson("C", weeksAhead: 0)

        #expect(r.thisWeek == "C")
        #expect(cycle(r) == ["C", "A", "B"])
    }

    @Test func settingNextWeekDoesNotDisturbThisWeek() {
        var r = rota(["A", "B", "C"])
        #expect(r.thisWeek == "A")

        r.setPerson("C", weeksAhead: 1)

        #expect(r.thisWeek == "A")       // untouched
        #expect(r.nextWeek == "C")
        #expect(cycle(r) == ["A", "C", "B"])
    }

    @Test func settingLastWeekDisturbsNeitherThisNorNext() {
        var r = rota(["A", "B", "C", "D"])
        let before = (this: r.thisWeek, next: r.nextWeek)

        r.setPerson("C", weeksAhead: -1)

        #expect(r.lastWeek == "C")
        #expect(r.thisWeek == before.this)
        #expect(r.nextWeek == before.next)
    }

    /// Only the person named moves. Somebody who already held the week being
    /// given away has to go somewhere, and that somewhere is the slot vacated.
    @Test func theOnlyPersonDisplacedIsTheOneWhoHeldThatWeek() {
        var r = rota(["A", "B", "C"])   // last C, this A, next B

        r.setPerson("C", weeksAhead: 1)

        #expect(r.thisWeek == "A")      // untouched
        #expect(r.nextWeek == "C")
        #expect(r.person(weeksAhead: 2) == "B")   // B slides along
    }

    @Test func settingAWeekToWhoAlreadyHasItChangesNothing() {
        var r = rota(["A", "B", "C"])
        let before = cycle(r)

        r.setPerson(r.nextWeek, weeksAhead: 1)

        #expect(cycle(r) == before)
    }

    /// After the named person is placed, the rest of the cycle follows in the
    /// order it already had, and keeps repeating.
    @Test func theCycleCarriesOnThroughTheRestInOrder() {
        var r = rota(["A", "B", "C"])

        r.setPerson("B", weeksAhead: 0)

        #expect(r.thisWeek == "B")
        #expect(r.person(weeksAhead: 1) == "A")
        #expect(r.person(weeksAhead: 2) == "C")
        #expect(r.person(weeksAhead: 3) == "B")
    }

    @Test func tappingACircleSetsThisWeek() {
        var r = rota(["A", "B", "C"])

        r.setCurrent(to: 2)

        #expect(r.thisWeek == "C")
    }

    // MARK: Changing the list

    @Test func addingSomebodyKeepsThePhase() {
        var r = rota(["A", "B", "C"])
        r.setPerson("B", weeksAhead: 0)

        r.addPerson("D")

        #expect(r.thisWeek == "B")
        #expect(r.people.contains("D"))
    }

    @Test func addingSomebodyPutsThemAtTheEndOfTheCycle() {
        var r = rota(["A", "B", "C"])

        r.addPerson("D")

        #expect(r.thisWeek == "A")
        #expect(cycle(r) == ["A", "B", "C", "D"])
    }

    @Test func addingADuplicateNameDoesNothing() {
        var r = rota(["A", "B"])

        r.addPerson("A")

        #expect(r.people == ["A", "B"])
    }

    @Test func removingSomebodyElseKeepsThePhase() {
        var r = rota(["A", "B", "C", "D"])
        r.setPerson("C", weeksAhead: 0)

        r.removePerson(at: r.people.firstIndex(of: "A")!)

        #expect(r.thisWeek == "C")
    }

    @Test func removingThePersonOnDutyPassesToTheNext() {
        var r = rota(["A", "B", "C"])
        r.setPerson("A", weeksAhead: 0)

        r.removePerson(at: 0)

        #expect(r.thisWeek == "B")
    }

    @Test func removingShiftsTheMeIndexWithTheList() {
        var r = rota(["A", "B", "C"])
        r.me = 2

        r.removePerson(at: 0)

        #expect(r.people == ["B", "C"])
        #expect(r.people[r.me] == "C")
    }

    @Test func refusesToEmptyTheRota() {
        var r = rota(["A"])

        r.removePerson(at: 0)

        #expect(r.people == ["A"])
    }

    // MARK: The reported case

    /// Dheeraj two weeks ago, Agilan last week, me this week. Set through the
    /// pickers, the cycle should carry on to Dheeraj next.
    @Test func theStatedHistoryCyclesOnToDheeraj() {
        var r = rota(["Dheeraj", "Agilan", "Me"])

        r.setPerson("Me", weeksAhead: 0)
        r.setPerson("Agilan", weeksAhead: -1)

        #expect(r.lastWeek == "Agilan")
        #expect(r.thisWeek == "Me")
        #expect(r.nextWeek == "Dheeraj")
        #expect(r.person(weeksAhead: -2) == "Dheeraj")
        #expect(r.person(weeksAhead: 2) == "Agilan")
    }

    /// And setting next week explicitly is honoured without this week moving.
    @Test func nextWeekCanBeSetOutrightWithoutMovingThisWeek() {
        var r = rota(["Dheeraj", "Agilan", "Me"])
        r.setPerson("Me", weeksAhead: 0)

        r.setPerson("Agilan", weeksAhead: 1)

        #expect(r.thisWeek == "Me")
        #expect(r.nextWeek == "Agilan")
        #expect(r.person(weeksAhead: 2) == "Dheeraj")
    }

    // MARK: Persistence

    @Test func decodesADocumentFromBeforeTheRecordsExisted() throws {
        let old = """
        {"anchorIndex":1,"anchorMonday":"2026-09-28T00:00:00Z","me":0,"people":["A","B"]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let r = try decoder.decode(TrashRota.self, from: Data(old.utf8))

        #expect(r.people == ["A", "B"])
        #expect(r.anchorIndex == 1)
    }

    /// Documents written while the credit ledger existed still open; the
    /// records and balances in them are simply dropped.
    @Test func dropsTheOldRecordsAndBalances() throws {
        let old = """
        {"anchorIndex":0,"anchorMonday":"2026-09-28T00:00:00Z","me":0,
         "people":["A","B"],"balances":{"A":-0.5,"B":0.5},
         "records":[{"id":"81DB66BF-9040-434F-B31F-176DF9959B3F",
                     "date":"2026-09-28T00:00:00Z","didIt":"B"}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let r = try decoder.decode(TrashRota.self, from: Data(old.utf8))
        #expect(r.people == ["A", "B"])

        let written = String(data: try encoder.encode(r), encoding: .utf8) ?? ""
        #expect(!written.contains("balances"))
        #expect(!written.contains("records"))
    }

    @Test func survivesARoundTrip() throws {
        var r = rota(["Dheeraj", "Agilan", "Me"])
        r.setPerson("Me", weeksAhead: 0)
        r.me = r.people.firstIndex(of: "Me")!

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let back = try decoder.decode(TrashRota.self, from: encoder.encode(r))

        #expect(back.thisWeek == "Me")
        #expect(back.nextWeek == "Dheeraj")
        #expect(back.people[back.me] == "Me")
    }

    // MARK: Which week the card is showing

    /// A date at a known weekday, so the roll can be checked day by day.
    private func day(_ weekday: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let monday = TrashRota.mondayOf(Date())
        // weekday: 2 = Monday ... 1 = Sunday, which is six days on.
        let offset = weekday == 1 ? 6 : weekday - 2
        return cal.date(byAdding: .day, value: offset, to: monday)!
    }

    @Test func theNextCollectionIsTodayOnACollectionDay() {
        let monday = day(2), thursday = day(5)

        #expect(TrashRota.nextCollection(after: monday) == monday)
        #expect(TrashRota.nextCollection(after: thursday) == thursday)
    }

    @Test func theNextCollectionIsThursdayMidweek() {
        #expect(TrashRota.nextCollection(after: day(3)) == day(5))   // Tue
        #expect(TrashRota.nextCollection(after: day(4)) == day(5))   // Wed
    }

    /// Once Thursday is done the next lot is Monday's, which is next week's.
    @Test func theNextCollectionRollsToMondayFromFriday() {
        let nextMonday = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: 7, to: day(2))!

        #expect(TrashRota.nextCollection(after: day(6)) == nextMonday)   // Fri
        #expect(TrashRota.nextCollection(after: day(7)) == nextMonday)   // Sat
        #expect(TrashRota.nextCollection(after: day(1)) == nextMonday)   // Sun
    }

    /// The complaint: on Sunday evening the card named the week that was
    /// ending, while the bins going out that night were the next person's.
    @Test func theCardNamesWhoseBinsAreNext() {
        var r = rota(["Dheeraj", "Agilan", "Me"])
        r.setPerson("Me", weeksAhead: 0)

        // Midweek it is still this week's person.
        #expect(r.activePerson(at: day(3)) == "Me")
        #expect(r.activeWeekLabel(at: day(3)) == "this week")

        // From Friday it is whoever has the Monday coming.
        #expect(r.activePerson(at: day(6)) == "Dheeraj")
        #expect(r.activePerson(at: day(1)) == "Dheeraj")      // Sunday
        #expect(r.activeWeekLabel(at: day(1)) == "next week")
    }

    /// The roll must not reorder anything: it only changes which week is read.
    @Test func rollingForwardDoesNotChangeTheRotation() {
        var r = rota(["Dheeraj", "Agilan", "Me"])
        r.setPerson("Me", weeksAhead: 0)
        let order = cycle(r)

        _ = r.activePerson(at: day(1))

        #expect(cycle(r) == order)
        #expect(r.thisWeek == "Me")          // the pickers still read the calendar
        #expect(r.nextWeek == "Dheeraj")
    }

    @Test func theLabelSaysWhichWeekSoARollIsNotASkip() {
        var r = rota(["A", "B"])
        r.setPerson("A", weeksAhead: 0)

        #expect(r.activeWeekLabel(at: day(2)) == "this week")
        #expect(r.activeWeekLabel(at: day(5)) == "this week")
        #expect(r.activeWeekLabel(at: day(6)) == "next week")
    }

    // MARK: What Siri says

    @Test func speaksTheWeekTheCardIsShowing() {
        var r = rota(["Dheeraj", "Agilan", "Me"])
        r.setPerson("Agilan", weeksAhead: 0)
        r.me = r.people.firstIndex(of: "Me")!

        #expect(r.spokenTurn(at: day(3)) == "This week is Agilan's.")
        #expect(r.spokenTurn(at: day(1)).hasPrefix("Next week is"))
        // Whatever it says, it names the person the card names.
        #expect(r.spokenTurn(at: day(1)).contains(r.activePerson(at: day(1))))
    }

    @Test func speaksInTheSecondPersonWhenItIsYours() {
        var r = rota(["A", "Me"])
        r.setPerson("Me", weeksAhead: 0)
        r.me = r.people.firstIndex(of: "Me")!

        #expect(r.spokenTurn(at: day(3)) == "The bins are yours this week.")
    }

    @Test func saysSoWhenNobodyIsInTheRota() {
        var r = TrashRota()
        r.people = []

        #expect(r.spokenTurn().contains("nobody"))
    }
}

/// Which person the card, the reminder and Siri name across a weekend.
///
/// Weeks run Monday to Sunday, so the bins going out on Sunday night are for
/// Monday's collection and belong to the *next* week's person. All three
/// surfaces derive that from `nextCollection`, which counts today — so once
/// Thursday's collection is done, everything points at Monday's.
///
/// Written because the three could drift apart silently: the card reads
/// `activePerson`, the reminder works from the collection date, and Siri
/// reads `spokenTurn`. Nothing would fail if one of them stopped agreeing.
struct TrashWeekendTests {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    /// November 2026: Mon 9 … Thu 12, Fri 13, Sat 14, Sun 15, Mon 16.
    private func at(_ day: Int, _ hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    /// A rota anchored to the week containing `when`, so people[0] holds it.
    private func rota(at when: Date) -> TrashRota {
        var r = TrashRota()
        r.people = ["A", "B", "C"]
        r.anchorIndex = 0
        r.anchorMonday = TrashRota.mondayOf(when)
        return r
    }

    /// How many weeks ahead of the calendar week the card is pointing.
    private func roll(_ when: Date) -> Int {
        let r = rota(at: when)
        return r.activeWeek(at: when) - r.weekIndex(of: when)
    }

    // MARK: The roll

    /// Monday to Thursday the card names the week you are standing in.
    @Test func staysOnThisWeekUntilThursdayIsDone() {
        #expect(roll(at(9, 9)) == 0)        // Monday, collection day
        #expect(roll(at(11, 19)) == 0)      // Wednesday evening, bins out
        #expect(roll(at(12, 9)) == 0)       // Thursday, collection day
    }

    /// From Friday both of this week's collections have gone, so the card is
    /// already talking about Monday's — which is next week's person.
    @Test func rollsForwardOnceThursdayIsPast() {
        #expect(roll(at(13, 12)) == 1)      // Friday
        #expect(roll(at(14, 12)) == 1)      // Saturday
        #expect(roll(at(15, 10)) == 1)      // Sunday morning
        #expect(roll(at(15, 19)) == 1)      // Sunday evening, bins out tonight
        #expect(roll(at(15, 23)) == 1)      // Sunday, late
    }

    /// And back to zero on Monday, naming the same person it named on
    /// Sunday — the roll is a change of label, never of person.
    @Test func mondayNamesWhoeverSundayPromised() {
        let sunday = at(15, 19)
        let monday = at(16, 9)

        // One rota, so both dates are measured against the same anchor.
        let r = rota(at: sunday)

        #expect(roll(sunday) == 1)
        #expect(roll(monday) == 0)
        #expect(r.weekIndex(of: sunday) + 1 == r.weekIndex(of: monday))

        // Sunday's "next week" and Monday's "this week" are the same person:
        // the roll changes the label, never who is up.
        #expect(r.activePerson(at: sunday) == r.activePerson(at: monday))
    }

    // MARK: What it says

    @Test func labelsTheRollSoItDoesNotReadAsASkip() {
        let r = rota(at: at(15, 19))

        #expect(r.activeWeekLabel(at: at(12, 9)) == "this week")
        #expect(r.activeWeekLabel(at: at(15, 19)) == "next week")
    }

    /// The card says which collection those bins are for, so "next week"
    /// has something concrete attached to it.
    @Test func namesTheCollectionTheBinsAreFor() {
        let r = rota(at: at(15, 19))

        #expect(r.nextCollectionText(at: at(15, 19)).contains("mon"))
        #expect(r.nextCollectionText(at: at(11, 19)).contains("thu"))
    }

    /// Siri reads from the same accessor as the card, so the two cannot
    /// disagree about who is up.
    @Test func siriAgreesWithTheCard() {
        var r = rota(at: at(15, 19))
        r.me = 0                            // "A" is me

        let sundayEvening = at(15, 19)
        let spoken = r.spokenTurn(at: sundayEvening)
        let onTheCard = r.activePerson(at: sundayEvening)

        #expect(spoken.lowercased().contains("next week"))
        // Either it names them, or it says they are mine — and they are only
        // mine when the card says so too.
        if r.isMyActiveWeek(at: sundayEvening) {
            #expect(spoken.contains("yours"))
            #expect(onTheCard == r.people[r.me])
        } else {
            #expect(spoken.contains(onTheCard))
        }
    }
}
