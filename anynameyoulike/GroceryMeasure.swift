import Foundation
import SwiftUI
import UserNotifications

// MARK: - Model

enum GroceryMeasure: String, Codable, CaseIterable, Identifiable {
    case count, weigh

    var id: String { rawValue }

    var label: String {
        self == .count ? "count what I use" : "weigh what's left"
    }
}

struct GroceryItem: Identifiable, Codable {
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
        measure == .count ? packSize : max(0, packSize - tare)
    }
}

struct UseEntry: Identifiable, Codable {
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

    init() { reload() }

    func reload() {
        let doc = Store.document
        items = doc.groceryItems

        let cutoff = Calendar.current.date(byAdding: .day, value: -45, to: Date()) ?? Date()
        log = doc.useLog.filter { $0.date >= cutoff }
    }

    func save() {
        Store.mutate {
            $0.groceryItems = items
            $0.useLog = log
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

    func logUse(_ item: GroceryItem, amount: Double) {
        guard let i = index(of: item), amount != 0 else { return }

        if amount > 0 {
            let taken = min(amount, items[i].remaining)
            guard taken > 0 else { return }
            items[i].remaining -= taken
            log.append(UseEntry(itemID: item.id, date: Date(), amount: taken))
        } else {
            let give = -amount
            items[i].remaining = min(items[i].fullAmount, items[i].remaining + give)
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

enum GroceryReminder {
    static let identifier = "groceryLogReminder"
    private static let enabledKey = "groceryReminderOn"
    private static let hourKey = "groceryReminderHour"
    private static let minuteKey = "groceryReminderMinute"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var hour: Int {
        get { UserDefaults.standard.object(forKey: hourKey) as? Int ?? 22 }
        set { UserDefaults.standard.set(newValue, forKey: hourKey) }
    }

    static var minute: Int {
        get { UserDefaults.standard.object(forKey: minuteKey) as? Int ?? 30 }
        set { UserDefaults.standard.set(newValue, forKey: minuteKey) }
    }

    static var timeText: String {
        String(format: "%d:%02d %@",
               hour % 12 == 0 ? 12 : hour % 12,
               minute,
               hour < 12 ? "am" : "pm")
    }

    @discardableResult
    static func apply() async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard isEnabled else { return false }

        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        let content = UNMutableNotificationContent()
        content.title = "Groceries"
        content.body = "Log what you got through today."
        content.sound = .default

        var parts = DateComponents()
        parts.hour = hour
        parts.minute = minute

        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
                )
            )
            return true
        } catch {
            return false
        }
    }
}
