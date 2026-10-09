import Foundation
import Testing
@testable import anynameyoulike

/// Logging a whole meal, and what Siri says about it. The spoken line is the
/// only feedback there is when the phone is locked, so it is part of the
/// behaviour rather than decoration.
struct MealTests {

    private func pantry(_ items: [GroceryItem]) -> Pantry {
        // Detached: these run inside the app, and a save would write over
        // the document the app is using.
        Pantry(items: items)
    }

    private func item(_ name: String, _ measure: GroceryMeasure,
                      unit: String, left: Double) -> GroceryItem {
        GroceryItem(
            name: name, measure: measure, unit: unit,
            packSize: max(left, 1), remaining: left, startRate: 1
        )
    }

    // MARK: Taking a meal off

    @Test func takesEveryPortionInOneGo() {
        let chicken = item("Chicken", .portion, unit: "g", left: 1000)
        let bread = item("Bread", .count, unit: "slices", left: 12)
        let p = pantry([chicken, bread])

        let lunch = Meal(name: "lunch", portions: [
            MealPortion(itemID: chicken.id, amount: 250),
            MealPortion(itemID: bread.id, amount: 4),
        ])

        let outcome = p.log(lunch)

        #expect(p.items[0].remaining == 750)
        #expect(p.items[1].remaining == 8)
        #expect(outcome.ranOut.isEmpty)
        #expect(outcome.logged.count == 2)
    }

    /// Each deduction is logged against its own item, which is what the rate
    /// maths reads. A meal must not become one lump entry.
    @Test func logsEachDeductionAgainstItsOwnItem() {
        let chicken = item("Chicken", .portion, unit: "g", left: 1000)
        let bread = item("Bread", .count, unit: "slices", left: 12)
        let p = pantry([chicken, bread])

        p.log(Meal(name: "lunch", portions: [
            MealPortion(itemID: chicken.id, amount: 250),
            MealPortion(itemID: bread.id, amount: 4),
        ]))

        #expect(p.log.count == 2)
        #expect(p.log.filter { $0.itemID == chicken.id }.first?.amount == 250)
        #expect(p.log.filter { $0.itemID == bread.id }.first?.amount == 4)
        #expect(p.usedToday(p.items[0]) == 250)
        #expect(p.usedToday(p.items[1]) == 4)
    }

    // MARK: Running out

    @Test func takesWhatIsThereAndSaysWhatRanOut() {
        let chicken = item("Chicken", .portion, unit: "g", left: 100)
        let bread = item("Bread", .count, unit: "slices", left: 12)
        let p = pantry([chicken, bread])

        let outcome = p.log(Meal(name: "lunch", portions: [
            MealPortion(itemID: chicken.id, amount: 250),
            MealPortion(itemID: bread.id, amount: 4),
        ]))

        #expect(p.items[0].remaining == 0)        // not negative
        #expect(p.items[1].remaining == 8)        // the rest still came off
        #expect(outcome.ranOut.map(\.name) == ["chicken"])
        #expect(outcome.spoken.contains("chicken ran out"))
        // The log records what was there, not what was asked for.
        #expect(p.log.first { $0.itemID == chicken.id }?.amount == 100)
    }

    @Test func nothingLeftAnywhereStillSaysSo() {
        let chicken = item("Chicken", .portion, unit: "g", left: 0)
        let p = pantry([chicken])

        let outcome = p.log(Meal(name: "dinner", portions: [
            MealPortion(itemID: chicken.id, amount: 150),
        ]))

        #expect(p.log.isEmpty)
        #expect(outcome.logged.isEmpty)
        #expect(outcome.spoken.contains("Nothing left for dinner"))
        #expect(outcome.spoken.contains("chicken ran out"))
    }

    @Test func aPortionForAnItemThatIsGoneIsSkipped() {
        let p = pantry([])

        let outcome = p.log(Meal(name: "lunch", portions: [
            MealPortion(itemID: UUID(), amount: 250),
        ]))

        #expect(outcome.lines.isEmpty)
        #expect(outcome.spoken.contains("nothing in it yet"))
    }

    // MARK: What Siri says

    @Test func readsAsASentence() {
        let chicken = item("Chicken", .portion, unit: "g", left: 1000)
        let bread = item("Bread", .count, unit: "slices", left: 12)
        let p = pantry([chicken, bread])

        let outcome = p.log(Meal(name: "lunch", portions: [
            MealPortion(itemID: chicken.id, amount: 250),
            MealPortion(itemID: bread.id, amount: 4),
        ]))

        #expect(outcome.spoken == "Logged 250 g of chicken and 4 slices of bread.")
    }

    @Test func listsThreeThingsWithoutACommaBeforeTheAnd() {
        let a = item("Chicken", .portion, unit: "g", left: 1000)
        let b = item("Bread", .count, unit: "slices", left: 12)
        let c = item("Cereal", .count, unit: "units", left: 5)
        let p = pantry([a, b, c])

        let outcome = p.log(Meal(name: "lunch", portions: [
            MealPortion(itemID: a.id, amount: 250),
            MealPortion(itemID: b.id, amount: 4),
            MealPortion(itemID: c.id, amount: 1),
        ]))

        #expect(outcome.spoken.contains("of chicken, 4 slices of bread and 1 units of cereal"))
    }

    @Test func wholeNumbersDoNotGrowDecimals() {
        #expect(MealOutcome.trim(250) == "250")
        #expect(MealOutcome.trim(2.5) == "2.5")
        #expect(MealOutcome.trim(1) == "1")
    }

    // MARK: Finding a meal by what it is called

    @Test func matchesTheSpokenNameWhateverTheCase() {
        let p = pantry([])
        p.meals = [Meal(name: "Lunch"), Meal(name: " Water ")]

        #expect(p.meal(named: "lunch")?.name == "Lunch")
        #expect(p.meal(named: "LUNCH")?.name == "Lunch")
        #expect(p.meal(named: "water")?.name == " Water ")
        #expect(p.meal(named: "supper") == nil)
    }

    @Test func theSpokenNameIsTrimmedAndLowercased() {
        #expect(Meal(name: "  Lunch ").spokenName == "lunch")
    }

    // MARK: Editing

    @Test func savingTwiceReplacesRatherThanDuplicating() {
        let p = pantry([])
        var lunch = Meal(name: "lunch")

        p.upsert(lunch)
        lunch.name = "brunch"
        p.upsert(lunch)

        #expect(p.meals.count == 1)
        #expect(p.meals[0].name == "brunch")
    }

    @Test func deletingRemovesOnlyThatMeal() {
        let p = pantry([])
        let lunch = Meal(name: "lunch")
        let dinner = Meal(name: "dinner")
        p.upsert(lunch)
        p.upsert(dinner)

        p.delete(lunch)

        #expect(p.meals.map(\.name) == ["dinner"])
    }
}
