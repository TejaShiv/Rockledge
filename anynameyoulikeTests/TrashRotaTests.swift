import Foundation
import Testing
@testable import anynameyoulike

/// Covers the rotation phase and the credit ledger. Everything here builds a
/// rota by hand and reads it back through the pure accessors, so nothing
/// touches Store or the document on disk.
struct TrashRotaTests {

    /// A rota of `names` with `anchorIndex` 0, anchored to this Monday, so
    /// week 0 is the current week and `people[0]` holds it.
    private func rota(_ names: [String]) -> TrashRota {
        var r = TrashRota()
        r.people = names
        r.anchorMonday = TrashRota.mondayOf(Date())
        r.anchorIndex = 0
        return r
    }

    private func collection(weeksAgo: Int, thursday: Bool = false) -> Date {
        let cal = TrashRota.gregorian
        let monday = cal.date(
            byAdding: .day, value: -7 * weeksAgo, to: TrashRota.mondayOf(Date())
        )!
        return thursday ? cal.date(byAdding: .day, value: 3, to: monday)! : monday
    }

    // MARK: Plain rotation

    @Test func rotatesOnePersonPerWeek() {
        let r = rota(["A", "B", "C"])
        #expect(r.thisWeek == "A")
        #expect(r.nextWeek == "B")
        #expect(r.lastWeek == "C")
        #expect(r.person(weeksAhead: 3) == "A")
    }

    @Test func settingATurnRephasesTheRotation() {
        var r = rota(["A", "B", "C"])

        r.setPerson("C", weeksAhead: 0)
        #expect(r.thisWeek == "C")
        #expect(r.nextWeek == "A")

        r.setPerson("B", weeksAhead: -1)
        #expect(r.lastWeek == "B")
        #expect(r.thisWeek == "C")

        r.setPerson("A", weeksAhead: 1)
        #expect(r.nextWeek == "A")
        #expect(r.thisWeek == "C")
    }

    @Test func addingSomebodyKeepsThePhase() {
        var r = rota(["A", "B", "C"])
        r.setPerson("B", weeksAhead: 0)

        r.addPerson("D")

        #expect(r.thisWeek == "B")
        #expect(r.people == ["A", "B", "C", "D"])
    }

    @Test func removingSomebodyElseKeepsThePhase() {
        var r = rota(["A", "B", "C", "D"])
        r.setPerson("C", weeksAhead: 0)

        r.removePerson(at: 0)   // drop A, who is not on this week

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
        r.me = 2                       // C is me

        r.removePerson(at: 0)          // drop A

        #expect(r.people == ["B", "C"])
        #expect(r.people[r.me] == "C")
    }

    // MARK: Credit

    @Test func standingInIsWorthHalfATurn() {
        var r = rota(["A", "B"])
        // A is due this week; B actually did Monday.
        r.swaps = [TrashSwap(date: collection(weeksAgo: 0), didIt: "B", dueWas: "A")]

        #expect(r.balance(for: "B") == 0.5)
        #expect(r.balance(for: "A") == -0.5)
    }

    @Test func followingTheScheduleCostsNothing() {
        let r = rota(["A", "B"])
        #expect(r.currentBalances.isEmpty)
    }

    @Test func twoStandInsSkipTheTurn() {
        var r = rota(["A", "B", "C"])
        // B covered both of A's collections two weeks ago, so B is a whole
        // turn up and A a whole turn down. A holds week 0 in plain rotation.
        r.swaps = [
            TrashSwap(date: collection(weeksAgo: 2), didIt: "B", dueWas: "A"),
            TrashSwap(date: collection(weeksAgo: 2, thursday: true), didIt: "B", dueWas: "A"),
        ]

        #expect(r.balance(for: "B") == 1.0)
        #expect(r.balance(for: "A") == -1.0)

        // Week 1 is B's in plain rotation, but B is a turn in credit, so B is
        // skipped and the week goes to A, who is furthest in debt.
        #expect(r.person(weeksAhead: 1) == "A")

        // Settled: both are square again afterwards.
        let after = r.ledger(covering: 0...1).balances
        #expect(after["A"] == nil)
        #expect(after["B"] == nil)
    }

    @Test func onlyOnePersonIsScheduledInASkippedWeek() {
        var r = rota(["A", "B", "C"])
        r.swaps = [
            TrashSwap(date: collection(weeksAgo: 2), didIt: "B", dueWas: "A"),
            TrashSwap(date: collection(weeksAgo: 2, thursday: true), didIt: "B", dueWas: "A"),
        ]

        let ledger = r.ledger(covering: 0...3)
        for week in r.currentWeek...(r.currentWeek + 3) {
            #expect(ledger.assignee[week] != nil)
        }
        #expect(ledger.assignee[r.currentWeek + 1] == "A")
    }

    @Test func creditOnlySettlesAtTheNextTurn() {
        var r = rota(["A", "B", "C"])
        // B covers both of A's collections during A's own current week.
        r.swaps = [
            TrashSwap(date: collection(weeksAgo: 0), didIt: "B", dueWas: "A"),
            TrashSwap(date: collection(weeksAgo: 0, thursday: true), didIt: "B", dueWas: "A"),
        ]

        // This week was already assigned before the swaps landed.
        #expect(r.thisWeek == "A")
        // B's turn is next week, and B is now a turn up, so A takes it.
        #expect(r.nextWeek == "A")
    }

    @Test func aCorrectionRecordedAfterTheBoundaryStillSettles() {
        var r = rota(["A", "B", "C"])
        // Recorded now, but dated to a collection two weeks back: the skip it
        // causes must still show up in the upcoming schedule.
        r.record("B", for: collection(weeksAgo: 2), due: "A")
        r.record("B", for: collection(weeksAgo: 2, thursday: true), due: "A")

        #expect(r.balance(for: "B") == 1.0)
        #expect(r.person(weeksAhead: 1) == "A")
    }

    @Test func namingThePersonWhoWasDueClearsTheCorrection() {
        var r = rota(["A", "B"])
        let day = collection(weeksAgo: 0)

        r.record("B", for: day, due: "A")
        #expect(r.swaps.count == 1)

        r.record("A", for: day, due: "A")
        #expect(r.swaps.isEmpty)
        #expect(r.currentBalances.isEmpty)
    }

    @Test func rephasingDoesNotRewriteWhoOwedWhat() {
        var r = rota(["A", "B", "C"])
        r.record("B", for: collection(weeksAgo: 0), due: "A")

        r.setPerson("C", weeksAhead: 0)

        // The debt stays with A, who was due when it was recorded.
        #expect(r.balance(for: "A") == -0.5)
        #expect(r.balance(for: "B") == 0.5)
    }

    // MARK: Recent collections

    @Test func recentCollectionsAreTheLastFourNewestFirst() {
        let r = rota(["A", "B"])
        let recent = r.recentCollections()

        #expect(recent.count == 4)
        #expect(recent[0].date > recent[1].date)
        #expect(recent[3].date < recent[0].date)
        for slot in recent {
            #expect(slot.date <= TrashRota.gregorian.startOfDay(for: Date()))
            #expect(slot.didIt == slot.due)       // nothing logged, so pre-selected
            #expect(!slot.isCorrected)
        }
    }

    @Test func aRecordedCollectionComesBackPreSelected() {
        var r = rota(["A", "B"])
        let day = r.recentCollections()[0].date
        let due = r.recentCollections()[0].due
        let other = r.people.first { $0 != due }!

        r.record(other, for: day, due: due)

        let slot = r.recentCollections()[0]
        #expect(slot.didIt == other)
        #expect(slot.isCorrected)
    }

    // MARK: Labels

    @Test func balancesReadAsHalvesAndWholes() {
        #expect(TrashRota.balanceLabel(0) == nil)
        #expect(TrashRota.balanceLabel(0.5) == "½ owed")
        #expect(TrashRota.balanceLabel(-0.5) == "½ owing")
        #expect(TrashRota.balanceLabel(1) == "1 owed")
        #expect(TrashRota.balanceLabel(-1.5) == "1½ owing")
        #expect(TrashRota.balanceLabel(2) == "2 owed")
    }

    // MARK: Persistence shape

    @Test func decodesADocumentWrittenBeforeCreditExisted() throws {
        let old = """
        {"anchorIndex":1,"anchorMonday":"2026-09-28T00:00:00Z","me":0,"people":["A","B"]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let r = try decoder.decode(TrashRota.self, from: Data(old.utf8))

        #expect(r.people == ["A", "B"])
        #expect(r.anchorIndex == 1)
        #expect(r.swaps.isEmpty)
        #expect(r.balances.isEmpty)
    }

    @Test func swapsAndBalancesSurviveARoundTrip() throws {
        var r = rota(["A", "B"])
        r.swaps = [TrashSwap(date: collection(weeksAgo: 0), didIt: "B", dueWas: "A")]
        r.balances = r.currentBalances

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let back = try decoder.decode(TrashRota.self, from: encoder.encode(r))

        #expect(back.swaps.count == 1)
        #expect(back.swaps[0].didIt == "B")
        #expect(back.balances["B"] == 0.5)
    }
}
