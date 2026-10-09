import AppIntents
import Foundation

// MARK: - What Siri can refer to

struct MealEntity: AppEntity {
    var id: UUID
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Meal"
    static var defaultQuery = MealQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

nonisolated struct MealQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [MealEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    /// Everything, so Siri learns the names and the Shortcuts app can offer
    /// them without the app being opened.
    @MainActor
    func suggestedEntities() async throws -> [MealEntity] { all() }

    @MainActor
    private func all() -> [MealEntity] {
        Shared.pantry.reload()
        return Shared.pantry.meals.map { MealEntity(id: $0.id, name: $0.spokenName) }
    }
}

struct GroceryEntity: AppEntity {
    var id: UUID
    var name: String
    var unit: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Item"
    static var defaultQuery = GroceryQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

nonisolated struct GroceryQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [GroceryEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [GroceryEntity] { all() }

    @MainActor
    private func all() -> [GroceryEntity] {
        Shared.pantry.reload()
        return Shared.pantry.items.map {
            GroceryEntity(id: $0.id, name: $0.name.lowercased(), unit: $0.unit)
        }
    }
}

// MARK: - Logging a whole meal

/// "Had lunch" takes every portion of that meal off in one go.
///
/// Never opens the app: this has to work from the lock screen, which is where
/// it will mostly be used.
struct LogMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a meal"
    static var description = IntentDescription(
        "Takes everything in a meal off what you have left."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Meal")
    var meal: MealEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let pantry = Shared.pantry
        pantry.reload()

        guard let stored = pantry.meals.first(where: { $0.id == meal.id })
                ?? pantry.meal(named: meal.name)
        else {
            return .result(dialog: "I could not find a meal called \(meal.name).")
        }

        let outcome = pantry.log(stored)
        return .result(dialog: IntentDialog(stringLiteral: outcome.spoken))
    }
}

// MARK: - Logging one item

/// "Used three eggs", without having to have defined a meal for it.
struct LogItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Log an item"
    static var description = IntentDescription(
        "Takes an amount of one item off what you have left."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Item")
    var item: GroceryEntity

    @Parameter(title: "Amount", default: 1)
    var amount: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let pantry = Shared.pantry
        pantry.reload()

        guard let stored = pantry.item(withID: item.id) else {
            return .result(dialog: "I could not find \(item.name).")
        }

        let result = pantry.take(stored, amount: amount)
        let unit = stored.unit
        let name = stored.name.lowercased()

        if result.taken == 0 {
            return .result(dialog: "There is no \(name) left.")
        }
        if result.short > 0 {
            return .result(dialog: IntentDialog(stringLiteral:
                "Logged \(MealOutcome.trim(result.taken)) \(unit) of \(name). "
                + "That is all there was — \(name) ran out."
            ))
        }
        return .result(dialog: IntentDialog(stringLiteral:
            "Logged \(MealOutcome.trim(result.taken)) \(unit) of \(name). "
            + "\(MealOutcome.trim(stored.remaining - result.taken)) \(unit) left."
        ))
    }
}

// MARK: - What Siri listens for
