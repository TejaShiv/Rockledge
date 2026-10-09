import Foundation
import SwiftUI
import UserNotifications

// MARK: - Model

/// How an item's usage gets recorded.
///
/// The raw values are what is already written in kalla.json, so adding a mode
/// leaves every existing item exactly where it was.
nonisolated enum GroceryMeasure: String, Codable, CaseIterable, Identifiable {
    /// Eggs, slices: one tap per unit, or type a number when it was a lot.
    case count
    /// Chicken: take 250g out of the pack and type 250.
    case portion
    /// The pack goes on the scale and the reading is the new truth.
    case weigh

    var id: String { rawValue }

    /// Worded to be impossible to mix up: what you do, not what you have.
    /// "Count what I use" and "type what I used" were two ways of saying the
    /// same thing.
    var label: String {
        switch self {
        case .count: return "tap off each one"
        case .portion: return "type the amount I take"
        case .weigh: return "weigh what's left"
        }
    }

    var hint: String {
        switch self {
        case .count: return "eggs, slices — one tap each, or type a number"
        case .portion: return "250g of chicken out of the pack"
        case .weigh: return "the whole pack on the scale"
        }
    }

    /// Whether the number you give is how much you took, rather than how much
    /// is left.
    var recordsUsage: Bool { self != .weigh }

    var defaultUnit: String {
        switch self {
        case .count: return "units"
        case .portion, .weigh: return "g"
        }
    }
}

nonisolated struct GroceryItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var measure: GroceryMeasure
    var unit: String            // eggs, slices, units, g
    var packSize: Double        // count: units per pack. weigh: full gross weight
    var tare: Double = 0        // weigh only: empty container
    var remaining: Double       // count: units. weigh: usable grams
    var startRate: Double       // per-day estimate given when added
    var openedAt: Date = Date()
    var lastOrdered: Date?

    var fullAmount: Double {
        // Only a weighed pack has a container to subtract.
        measure == .weigh ? max(0, packSize - tare) : packSize
    }
}

nonisolated struct UseEntry: Identifiable, Codable {
    var id = UUID()
    var itemID: UUID
    var date: Date
    var amount: Double
}

// MARK: - Store

@Observable
final class Pantry {
    var items: [GroceryItem] = []
    var log: [UseEntry] = []
    var meals: [Meal] = []

    init() { reload() }

    /// A pantry with nothing behind it.
    ///
    /// For tests: the test bundle runs inside the app, so a save here would
    /// write over whatever the app itself is doing to the same document.
    init(items: [GroceryItem], log: [UseEntry] = [], meals: [Meal] = []) {
        self.items = items
        self.log = log
        self.meals = meals
        self.detached = true
    }

    private var detached = false

    func reload() {
        let doc = Store.document
        items = doc.groceryItems
        meals = doc.meals

        let cutoff = Calendar.current.date(byAdding: .day, value: -45, to: Date()) ?? Date()
        log = doc.useLog.filter { $0.date >= cutoff }
    }

    func save() {
        guard !detached else { return }
        Store.mutate {
            $0.groceryItems = items
            $0.useLog = log
            $0.meals = meals
        }
    }

    // MARK: Rate

    /// Observed daily burn over the last fortnight, blended with the
    /// starting estimate until there are a few real days to go on.
    func rate(for item: GroceryItem) -> Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fortnight = cal.date(byAdding: .day, value: -13, to: today) ?? today
        let since = max(fortnight, cal.startOfDay(for: item.openedAt))

        let entries = log.filter { $0.itemID == item.id && $0.date >= since }
        let loggedDays = Set(entries.map { cal.startOfDay(for: $0.date) }).count
        guard loggedDays > 0 else { return max(item.startRate, 0.001) }

        let elapsed = max(1, (cal.dateComponents([.day], from: since, to: today).day ?? 0) + 1)
        let observed = entries.reduce(0) { $0 + $1.amount } / Double(elapsed)

        let trust = min(1, Double(loggedDays) / 4)
        return max(observed * trust + item.startRate * (1 - trust), 0.001)
    }

    func daysLeft(for item: GroceryItem) -> Double {
        max(0, item.remaining) / rate(for: item)
    }

    func usedToday(_ item: GroceryItem) -> Double {
        let today = Calendar.current.startOfDay(for: Date())
        return log
            .filter { $0.itemID == item.id && $0.date >= today }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: Mutations

    func index(of item: GroceryItem) -> Int? {
        items.firstIndex { $0.id == item.id }
    }

    /// Takes what it can and says how much was missing, for callers that
    /// have to explain themselves — Siri cannot show a half-filled bar.
    @discardableResult
    func take(_ item: GroceryItem, amount: Double) -> (taken: Double, short: Double) {
        guard let i = index(of: item), amount > 0 else { return (0, 0) }

        let taken = min(amount, max(0, items[i].remaining))
        if taken > 0 {
            items[i].remaining -= taken
            log.append(UseEntry(itemID: item.id, date: Date(), amount: taken))
            save()
        }
        return (taken, amount - taken)
    }

    func logUse(_ item: GroceryItem, amount: Double) {
        guard let i = index(of: item), amount != 0 else { return }

        if amount > 0 {
            let taken = min(amount, items[i].remaining)
            guard taken > 0 else { return }
            items[i].remaining -= taken
            log.append(UseEntry(itemID: item.id, date: Date(), amount: taken))
        } else {
            let give = -amount
            // Not capped at a pack either: undoing a use on top of loose
            // stock has to be able to put it back where it was.
            items[i].remaining += give
            let today = Calendar.current.startOfDay(for: Date())
            if let last = log.lastIndex(where: { $0.itemID == item.id && $0.date >= today }) {
                log[last].amount -= give
                if log[last].amount <= 0 { log.remove(at: last) }
            }
        }
        save()
    }

    /// Weigh items: the scale reading is the new truth.
    func setGross(_ item: GroceryItem, gross: Double) {
        guard let i = index(of: item) else { return }
        let net = max(0, gross - items[i].tare)
        let consumed = max(0, items[i].remaining - net)
        items[i].remaining = net
        if consumed > 0 {
            log.append(UseEntry(itemID: item.id, date: Date(), amount: consumed))
        }
        save()
    }

    func restock(_ item: GroceryItem) {
        guard let i = index(of: item) else { return }
        items[i].remaining = items[i].fullAmount
        items[i].openedAt = Date()
        items[i].lastOrdered = nil
        save()
    }

    func markOrdered(_ item: GroceryItem) {
        guard let i = index(of: item) else { return }
        items[i].lastOrdered = Date()
        save()
    }

    // MARK: Meals

    func item(withID id: UUID) -> GroceryItem? {
        items.first { $0.id == id }
    }

    func meal(named spoken: String) -> Meal? {
        meals.first { $0.spokenName == spoken.lowercased() }
    }

    func upsert(_ meal: Meal) {
        if let i = meals.firstIndex(where: { $0.id == meal.id }) {
            meals[i] = meal
        } else {
            meals.append(meal)
        }
        save()
    }

    func delete(_ meal: Meal) {
        meals.removeAll { $0.id == meal.id }
        save()
    }

    /// Deducts every portion of a meal in one go.
    ///
    /// Each portion is logged against its own item, so the rate maths sees
    /// exactly what it would have seen had each been entered by hand. An item
    /// without enough left gives what it has and says how much was missing:
    /// the log records what was actually there, not what was asked for.
    @discardableResult
    func log(_ meal: Meal) -> MealOutcome {
        var outcome = MealOutcome(meal: meal.spokenName)

        for portion in meal.portions {
            guard let item = item(withID: portion.itemID) else { continue }
            let result = take(item, amount: portion.amount)

            outcome.lines.append(
                MealOutcome.Line(
                    name: item.name.lowercased(),
                    taken: result.taken,
                    short: result.short,
                    unit: item.unit
                )
            )
        }
        return outcome
    }

    func upsert(_ item: GroceryItem) {
        if let i = index(of: item) {
            items[i] = item
        } else {
            items.append(item)
        }
        save()
    }

    func delete(_ item: GroceryItem) {
        items.removeAll { $0.id == item.id }
        log.removeAll { $0.itemID == item.id }
        save()
    }

    // MARK: Ordering view

    /// Anything inside the shop cycle, soonest first. Two weeks of stock is hidden.
    func runningLow(horizon: Double = 14) -> [GroceryItem] {
        items
            .filter { daysLeft(for: $0) <= horizon }
            .sorted { daysLeft(for: $0) < daysLeft(for: $1) }
    }

    var mostUrgent: GroceryItem? {
        items.min { daysLeft(for: $0) < daysLeft(for: $1) }
    }
}

// MARK: - Nightly log reminder
