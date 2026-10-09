import AppIntents
import HealthKit
import UserNotifications

// MARK: - Write ledger

nonisolated struct SampleRef: Codable {
    let id: UUID
    let amount: Int
}

nonisolated struct WriteBatch: Codable {
    let date: Date
    let samples: [SampleRef]

    var total: Int { samples.reduce(0) { $0 + $1.amount } }
}

enum WriteLedger {
    static func load() -> [WriteBatch] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return Store.document.stepLedger.filter { $0.date >= startOfDay }
    }

    static func save(_ batches: [WriteBatch]) {
        Store.mutate { $0.stepLedger = Array(batches.suffix(40)) }
    }

    static func append(_ batch: WriteBatch) {
        save(load() + [batch])
    }

    static func clear() {
        Store.mutate { $0.stepLedger = [] }
    }

    static var lastTotal: Int? { load().last?.total }

    /// Everything this app has put into Health today. The reduction budget.
    static var ownTotalToday: Int {
        load().reduce(0) { $0 + $1.total }
    }
}

// MARK: - Top up intent

struct TopUpStepsIntent: AppIntent {
    static var title: LocalizedStringResource = "Top Up Steps"
    static var description = IntentDescription(
        "Checks today's step total and tops it up to the target only if it falls short."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Only if below", default: 10000)
    var threshold: Int

    @Parameter(title: "Top up to", default: 11000)
    var targetTotal: Int

    @Parameter(title: "Notify when done", default: true)
    var notify: Bool

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let writer = StepWriter()

        guard let current = await writer.todayTotal() else {
            let line = "Could not read Health. Unlock the phone and try again."
            if notify { await Notifier.send(title: "Top up failed", body: line) }
            return .result(dialog: IntentDialog(stringLiteral: line))
        }

        guard current < threshold else {
            let line = "Already at \(current.formatted(.number)). Nothing to do."
            return .result(dialog: IntentDialog(stringLiteral: line))
        }

        let amount = targetTotal - current
        guard amount > 0 else {
            let line = "Already at \(current.formatted(.number))."
            return .result(dialog: IntentDialog(stringLiteral: line))
        }

        let outcome = await writer.write(total: amount)

        switch outcome {
        case .success(let written):
            let line = "Added \(written.formatted(.number)). Now at \(targetTotal.formatted(.number))."
            if notify { await Notifier.send(title: "Steps topped up", body: line) }
            return .result(dialog: IntentDialog(stringLiteral: line))
        case .failure(let reason):
            if notify { await Notifier.send(title: "Top up failed", body: reason) }
            return .result(dialog: IntentDialog(stringLiteral: reason))
        }
    }
}

// MARK: - Plain write intent

struct WriteStepsIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Steps"
    static var description = IntentDescription("Adds a fixed number of steps to Apple Health.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Step Count", default: 1000)
    var stepCount: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await StepWriter().write(total: stepCount)

        switch outcome {
        case .success(let written):
            return .result(dialog: IntentDialog(stringLiteral: "Added \(written.formatted(.number)) steps."))
        case .failure(let reason):
            return .result(dialog: IntentDialog(stringLiteral: reason))
        }
    }
}

/// The app gets exactly one of these, so everything Siri can say lives here.
///
/// Phrases are matched literally, so each wording is spelled out rather than
/// hoping one generalises. Every phrase carries ${applicationName}, which
/// resolves at runtime to the display name — Tally.
struct StepShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TopUpStepsIntent(),
            phrases: ["Top up steps with \(.applicationName)"],
            shortTitle: "Top Up Steps",
            systemImageName: "figure.walk"
        )
        AppShortcut(
            intent: WriteStepsIntent(),
            phrases: ["Add steps with \(.applicationName)"],
            shortTitle: "Add Steps",
            systemImageName: "plus"
        )
        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                // Imperative first. A verb at the front marks the utterance
                // as a command; narration gets read as a sentence about the
                // day and matched against something else.
                "Log \(\.$meal) in \(.applicationName)",
                "Log my \(\.$meal) in \(.applicationName)",
                "Record \(\.$meal) in \(.applicationName)",
                "Add \(\.$meal) to \(.applicationName)",
                // Narration, kept as fallbacks. "in" rather than "with":
                // Tally is a plausible name for a person, and "had lunch
                // with Tally" is a sentence about company, not an app.
                "Had \(\.$meal) in \(.applicationName)",
                "Had my \(\.$meal) in \(.applicationName)",
                "I had \(\.$meal) in \(.applicationName)",
                // Bare, for when the meal name carries it: "water in Tally".
                "\(\.$meal) in \(.applicationName)",
            ],
            shortTitle: "Log a meal",
            systemImageName: "fork.knife"
        )

        AppShortcut(
            intent: LogItemIntent(),
            phrases: [
                // Imperative first, as above.
                "Take \(\.$item) off in \(.applicationName)",
                // "Log" belongs to meals now: registering it here too made
                // one phrase match two intents, and an item and a meal can
                // easily share a name.
                "Used \(\.$item) in \(.applicationName)",
                "I used \(\.$item) in \(.applicationName)",
            ],
            shortTitle: "Log an item",
            systemImageName: "minus.circle"
        )
    }
}

// MARK: - Notifications

enum Notifier {
    static func send(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await center.add(request)
    }
}

// MARK: - HealthKit

enum WriteOutcome {
    case success(Int)
    case failure(String)
}

enum UndoOutcome {
    case removed(total: Int, samples: Int)
    case nothingToUndo
    case failure(String)
}

struct StepWriter {
    private let healthStore = HKHealthStore()

    /// App Intents run `perform` off the main actor, and the project defaults
    /// types to @MainActor, so constructing one there needs this. The methods
    /// stay on the main actor, which costs a hop from the intent and nothing
    /// in the app. Store itself is safe from either side.
    nonisolated init() {}

    private var stepType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .stepCount)
    }

    private func authorize(_ type: HKQuantityType) async -> String? {
        do {
            try await healthStore.requestAuthorization(toShare: [type], read: [type])
            return nil
        } catch {
            return "Health access was refused. Turn it on in Settings, Health, Data Access and Devices."
        }
    }

    // MARK: Write

    func write(total: Int) async -> WriteOutcome {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .failure("Health data is not available on this device.")
        }
        guard let stepType else {
            return .failure("Could not find the step count type.")
        }
        guard total > 0 else {
            return .failure("Nothing to add.")
        }
        if let problem = await authorize(stepType) {
            return .failure(problem)
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let elapsed = now.timeIntervalSince(startOfDay)

        guard elapsed > 900 else {
            return .failure("Too early in the day to spread the steps out.")
        }

        let chunkCount = 16
        let chunkLength = elapsed / Double(chunkCount)
        let perChunk = total / chunkCount
        let remainder = total % chunkCount

        var samples: [HKQuantitySample] = []
        var refs: [SampleRef] = []

        for index in 0..<chunkCount {
            var amount = perChunk
            if index == chunkCount - 1 { amount += remainder }
            guard amount > 0 else { continue }

            let start = startOfDay.addingTimeInterval(Double(index) * chunkLength)
            let end = start.addingTimeInterval(chunkLength * 0.9)
            let sample = HKQuantitySample(
                type: stepType,
                quantity: HKQuantity(unit: .count(), doubleValue: Double(amount)),
                start: start,
                end: end
            )
            samples.append(sample)
            refs.append(SampleRef(id: sample.uuid, amount: amount))
        }

        do {
            try await healthStore.save(samples)
            WriteLedger.append(WriteBatch(date: now, samples: refs))
            return .success(total)
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("protected") || message.contains("locked") {
                return .failure("Phone was locked, so Health was sealed. Unlock and try again.")
            }
            return .failure("The write did not complete. \(error.localizedDescription)")
        }
    }

    // MARK: Reduce by an exact amount

    func reduce(by amount: Int) async -> UndoOutcome {
        guard amount > 0, let stepType else { return .nothingToUndo }
        if let problem = await authorize(stepType) { return .failure(problem) }

        var batches = WriteLedger.load()
        var doomed: [UUID] = []
        var collected = 0

        while collected < amount, let batch = batches.popLast() {
            var kept: [SampleRef] = []
            for sample in batch.samples.reversed() {
                if collected < amount {
                    doomed.append(sample.id)
                    collected += sample.amount
                } else {
                    kept.insert(sample, at: 0)
                }
            }
            if !kept.isEmpty {
                batches.append(WriteBatch(date: batch.date, samples: kept))
            }
        }

        guard !doomed.isEmpty else { return .nothingToUndo }

        do {
            let predicate = HKQuery.predicateForObjects(with: Set(doomed))
            let deleted = try await healthStore.deleteObjects(of: stepType, predicate: predicate)

            let overshoot = collected - amount
            if overshoot > 0 {
                let now = Date()
                let sample = HKQuantitySample(
                    type: stepType,
                    quantity: HKQuantity(unit: .count(), doubleValue: Double(overshoot)),
                    start: now.addingTimeInterval(-600),
                    end: now.addingTimeInterval(-300)
                )
                try await healthStore.save([sample])
                batches.append(
                    WriteBatch(date: now, samples: [SampleRef(id: sample.uuid, amount: overshoot)])
                )
            }

            WriteLedger.save(batches)
            return .removed(total: amount, samples: deleted)
        } catch {
            return .failure("The removal did not complete. \(error.localizedDescription)")
        }
    }

    func removeAllToday() async -> UndoOutcome {
        guard let stepType else { return .nothingToUndo }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date())

        do {
            let count = try await healthStore.deleteObjects(of: stepType, predicate: predicate)
            WriteLedger.clear()
            return count == 0 ? .nothingToUndo : .removed(total: 0, samples: count)
        } catch {
            return .failure("The removal did not complete. \(error.localizedDescription)")
        }
    }

    // MARK: Read

    func todayTotal() async -> Int? {
        guard HKHealthStore.isHealthDataAvailable(), let stepType else { return nil }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date())

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Int(sum.doubleValue(for: .count())))
            }
            healthStore.execute(query)
        }
    }
}
