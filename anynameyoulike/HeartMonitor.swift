import HealthKit
import Foundation

@Observable
final class HeartMonitor {
    var latestBPM: Int?
    var latestAt: Date?
    var restingBPM: Int?
    var todayRange: (low: Int, high: Int)?
    var hrv: Int?
    var spo2: Int?
    var sampleCountToday = 0

    private let store = HealthAuth.store
    private var observer: HKObserverQuery?

    private let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    private var heartRateType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .heartRate)
    }

    func start() async {
        guard let heartRateType else { return }
        await refresh()
        installObserver(for: heartRateType)
    }

    func stop() {
        if let observer { store.stop(observer) }
        observer = nil
    }

    private func installObserver(for type: HKQuantityType) {
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
            Task { await self?.refresh() }
            completion()
        }
        store.execute(query)
        observer = query
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }

    // MARK: Reads

    func refresh() async {
        async let latest = latestSample(.heartRate)
        async let range = todaySpan()
        async let resting = latestSample(.restingHeartRate)
        async let variability = latestSample(.heartRateVariabilitySDNN)
        async let oxygen = latestSample(.oxygenSaturation)
        async let count = todayCount()

        let (newest, span, rest, sdnn, ox, total) =
            await (latest, range, resting, variability, oxygen, count)

        await MainActor.run {
            if let newest {
                self.latestBPM = Int(newest.value.rounded())
                self.latestAt = newest.date
            }
            self.todayRange = span
            self.restingBPM = rest.map { Int($0.value.rounded()) }
            self.hrv = sdnn.map { Int($0.value.rounded()) }
            self.spo2 = ox.map { Int(($0.value * 100).rounded()) }
            self.sampleCountToday = total
        }
    }

    private func unit(for id: HKQuantityTypeIdentifier) -> HKUnit {
        switch id {
        case .heartRate, .restingHeartRate: return bpmUnit
        case .heartRateVariabilitySDNN: return .secondUnit(with: .milli)
        case .oxygenSaturation: return .percent()
        default: return .count()
        }
    }

    private func latestSample(
        _ id: HKQuantityTypeIdentifier
    ) async -> (value: Double, date: Date)? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let measure = unit(for: id)

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: (sample.quantity.doubleValue(for: measure), sample.endDate)
                )
            }
            store.execute(query)
        }
    }

    private func todaySpan() async -> (low: Int, high: Int)? {
        guard let heartRateType else { return nil }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date())

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: [.discreteMin, .discreteMax]
            ) { _, stats, _ in
                guard let low = stats?.minimumQuantity()?.doubleValue(for: self.bpmUnit),
                      let high = stats?.maximumQuantity()?.doubleValue(for: self.bpmUnit)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (Int(low.rounded()), Int(high.rounded())))
            }
            store.execute(query)
        }
    }

    private func todayCount() async -> Int {
        guard let heartRateType else { return 0 }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.count ?? 0)
            }
            store.execute(query)
        }
    }

    // MARK: Display

    var freshness: String? {
        guard let latestAt else { return nil }
        let minutes = Int(Date().timeIntervalSince(latestAt) / 60)

        if minutes < 2 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }
}
