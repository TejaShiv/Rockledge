import HealthKit
import Foundation

@Observable
final class SleepMonitor {
    struct Segment: Identifiable {
        let id = UUID()
        let stage: Stage
        let start: Date
        let end: Date

        var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
    }

    enum Stage: String {
        case deep, core, rem, awake

        var label: String { rawValue }
    }

    var segments: [Segment] = []
    var inBed: (start: Date, end: Date)?
    var diagnostic = ""

    private let store = HealthAuth.store

    private var sleepType: HKCategoryType? {
        HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
    }

    func start() async {
        await refresh()
    }

    /// Searches 48 hours back and keeps the most recent sleep block,
    /// splitting on gaps longer than four hours.
    func refresh() async {
        guard let sleepType else {
            await MainActor.run { self.diagnostic = "sleep type unavailable" }
            return
        }

        let windowStart = Date().addingTimeInterval(-48 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: Date())

        let raw: [HKCategorySample] = await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }

        let staged: [Segment] = raw.compactMap { sample in
            guard let stage = Self.stage(for: sample.value) else { return nil }
            return Segment(stage: stage, start: sample.startDate, end: sample.endDate)
        }

        // keep only the latest night
        var night: [Segment] = []
        for segment in staged.reversed() {
            if let earliest = night.first {
                let gap = earliest.start.timeIntervalSince(segment.end)
                if gap > 4 * 3600 { break }
            }
            night.insert(segment, at: 0)
        }

        let note: String
        if raw.isEmpty {
            note = "nothing in Health for the last 48h"
        } else if staged.isEmpty {
            note = "\(raw.count) samples found, none with stages"
        } else {
            note = ""
        }

        await MainActor.run {
            self.segments = night
            self.diagnostic = note
            if let first = night.first, let last = night.last {
                self.inBed = (first.start, last.end)
            } else {
                self.inBed = nil
            }
        }
    }

    private static func stage(for value: Int) -> Stage? {
        switch value {
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return .deep
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: return .core
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: return .rem
        case HKCategoryValueSleepAnalysis.awake.rawValue: return .awake
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return .core
        default: return nil
        }
    }

    // MARK: Derived

    var asleepMinutes: Int {
        segments.filter { $0.stage != .awake }.reduce(0) { $0 + $1.minutes }
    }

    func minutes(in stage: Stage) -> Int {
        segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.minutes }
    }

    var durationText: String {
        let total = asleepMinutes
        guard total > 0 else { return "—" }
        return "\(total / 60)h \(total % 60)m"
    }
}
