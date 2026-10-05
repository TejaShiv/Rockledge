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
}
