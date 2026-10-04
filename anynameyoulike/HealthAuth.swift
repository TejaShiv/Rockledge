//
//  HealthAuth.swift
//  anynameyoulike
//
//  Created by Tejas Shivaprasad on 10/1/26.
//


import HealthKit

/// One authorization request for every type the app touches.
/// Separate requests race and silently drop, which is why sleep came back empty.
enum HealthAuth {
    static let store = HKHealthStore()

    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(hr)
        }
        if let resting = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(resting)
        }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        if let spo2 = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            types.insert(spo2)
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    private static var shareTypes: Set<HKSampleType> {
        guard let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }
        return [steps]
    }

    @discardableResult
    static func request() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            return true
        } catch {
            return false
        }
    }
}