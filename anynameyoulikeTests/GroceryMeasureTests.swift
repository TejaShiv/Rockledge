import Foundation
import Testing
@testable import anynameyoulike

/// The three ways of recording usage, and the deduction that has to refuse to
/// go negative.
struct GroceryMeasureTests {

    private func item(_ measure: GroceryMeasure,
                      pack: Double, left: Double, tare: Double = 0) -> GroceryItem {
        GroceryItem(
            name: "x", measure: measure, unit: measure.defaultUnit,
            packSize: pack, tare: tare, remaining: left, startRate: 1
        )
    }

    // MARK: Nothing already stored may shift

    /// The raw values are what is written in kalla.json. Adding a mode must
    /// not move an existing item into a different one.
    @Test func theStoredNamesAreUnchanged() {
        #expect(GroceryMeasure.count.rawValue == "count")
        #expect(GroceryMeasure.weigh.rawValue == "weigh")
        #expect(GroceryMeasure.portion.rawValue == "portion")
    }

    @Test func anItemWrittenBeforePortionExistedStillReads() throws {
        let old = """
        {"id":"81DB66BF-9040-434F-B31F-176DF9959B3F","measure":"count","name":"Eggs",
         "openedAt":"2026-10-04T22:22:43Z","packSize":12,"remaining":9,
         "startRate":2,"tare":0,"unit":"units"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let back = try decoder.decode(GroceryItem.self, from: Data(old.utf8))

        #expect(back.measure == .count)
        #expect(back.remaining == 9)
        #expect(back.fullAmount == 12)
    }

    /// A weighed pack still subtracts its container, and nothing else does.
    @Test func onlyAWeighedPackHasATare() {
        #expect(item(.weigh, pack: 1000, left: 400, tare: 120).fullAmount == 880)
        #expect(item(.count, pack: 12, left: 9, tare: 120).fullAmount == 12)
        #expect(item(.portion, pack: 1000, left: 400, tare: 120).fullAmount == 1000)
    }

    @Test func aPortionItemIsMeasuredNotCounted() {
        #expect(GroceryMeasure.portion.recordsUsage)
        #expect(GroceryMeasure.count.recordsUsage)
        #expect(!GroceryMeasure.weigh.recordsUsage)
        #expect(GroceryMeasure.portion.defaultUnit == "g")
        #expect(GroceryMeasure.count.defaultUnit == "units")
    }

    /// The two modes that both take a typed number have to read differently,
    /// which is the whole point of renaming them.
    @Test func theModesDoNotReadAlike() {
        let labels = GroceryMeasure.allCases.map(\.label)

        #expect(Set(labels).count == 3)
        #expect(GroceryMeasure.count.label.contains("tap"))
        #expect(GroceryMeasure.portion.label.contains("type"))
        #expect(GroceryMeasure.weigh.label.contains("left"))
    }

    // MARK: Taking an amount

    @Test func takesWhatWasAskedFor() {
        let chicken = item(.portion, pack: 1000, left: 1000)
        let pantry = Pantry(items: [chicken])

        let result = pantry.take(chicken, amount: 250)

        #expect(result.taken == 250)
        #expect(result.short == 0)
        #expect(pantry.items[0].remaining == 750)
        #expect(pantry.log.count == 1)
        #expect(pantry.log[0].amount == 250)
    }

    /// Asking for more than is there logs what was there, not what was asked.
    @Test func neverGoesNegative() {
        let chicken = item(.portion, pack: 1000, left: 150)
        let pantry = Pantry(items: [chicken])

        let result = pantry.take(chicken, amount: 250)

        #expect(result.taken == 150)
        #expect(result.short == 100)
        #expect(pantry.items[0].remaining == 0)
        #expect(pantry.log.count == 1)
        #expect(pantry.log[0].amount == 150)   // the log matches reality
    }

    @Test func takingFromAnEmptyItemLogsNothing() {
        let chicken = item(.portion, pack: 1000, left: 0)
        let pantry = Pantry(items: [chicken])

        let result = pantry.take(chicken, amount: 250)

        #expect(result.taken == 0)
        #expect(result.short == 250)
        #expect(pantry.log.isEmpty)
    }

    @Test func ignoresNothingAndNegatives() {
        let chicken = item(.portion, pack: 1000, left: 500)
        let pantry = Pantry(items: [chicken])

        #expect(pantry.take(chicken, amount: 0).taken == 0)
        #expect(pantry.take(chicken, amount: -50).taken == 0)
        #expect(pantry.items[0].remaining == 500)
        #expect(pantry.log.isEmpty)
    }

    /// Typing a number on a count item is the same deduction as tapping that
    /// many times, so the rate maths cannot tell them apart.
    @Test func typingOnACountItemMatchesTapping() {
        let eggs = item(.count, pack: 12, left: 12)
        let tapped = Pantry(items: [eggs])
        let typed = Pantry(items: [eggs])

        for _ in 0..<3 { tapped.logUse(eggs, amount: 1) }
        typed.take(eggs, amount: 3)

        #expect(tapped.items[0].remaining == typed.items[0].remaining)
        #expect(tapped.log.reduce(0) { $0 + $1.amount }
                == typed.log.reduce(0) { $0 + $1.amount })
    }
}
