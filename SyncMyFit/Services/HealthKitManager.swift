//
//  HealthKitManager.swift
//  SyncMyFit
//
//  Created by Baranidharan Pasupathi on 2025-06-30.
//

import Foundation
import HealthKit

// MARK: - HealthKitManager

/// Manages authorization and write access to Apple HealthKit.
/// Supports syncing steps, heart rate, sleep, and calories from Google Health to Apple Health.
class HealthKitManager {
    
    // MARK: - Singleton
    
    /// Shared instance of the manager.
    static let shared = HealthKitManager()
    
    /// Core HealthKit store instance.
    private let healthStore = HKHealthStore()
    
    /// Private initializer to enforce singleton usage.
    private init() {}

    // MARK: - Authorization
    
    /// Requests write access to relevant HealthKit data types.
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, NSError(domain: "HealthKit not available", code: 0))
            return
        }

        let writeTypes: Set = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        healthStore.requestAuthorization(toShare: writeTypes, read: nil) { success, error in
            completion(success, error)
        }
    }

    // MARK: - Write Steps
    
    /// Writes step count data to HealthKit, after removing any existing data from this app on the same day.
    func writeSteps(_ steps: Int, date: Date = Date()) {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }

        let metadata = ["SyncSource": "Google Health"]

        deleteExistingSamples(for: stepType, date: date, metadataKey: "SyncSource") {
            let quantity = HKQuantity(unit: HKUnit.count(), doubleValue: Double(steps))
            let sample = HKQuantitySample(type: stepType, quantity: quantity, start: date, end: date, metadata: metadata)

            self.healthStore.save(sample) { success, error in
                if !success {
                    print("Error saving steps: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }

    // MARK: - Write Heart Rate
    
    /// Writes heart rate samples to HealthKit, one per value, tagged with Google Health origin.
    func writeHeartRates(_ bpmValues: [Int], date: Date = Date()) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        let metadata = ["SyncSource": "Google Health"]

        deleteExistingSamples(for: hrType, date: date, metadataKey: "SyncSource") {
            for bpm in bpmValues {
                let quantity = HKQuantity(unit: HKUnit.count().unitDivided(by: HKUnit.minute()), doubleValue: Double(bpm))
                let sample = HKQuantitySample(type: hrType, quantity: quantity, start: date, end: date, metadata: metadata)

                self.healthStore.save(sample) { success, error in
                    if !success {
                        print("Error saving heart rate: \(error?.localizedDescription ?? "Unknown error")")
                    }
                }
            }
        }
    }

    // MARK: - Write Sleep
    
    /// Writes a block of sleep data to HealthKit based on the given number of hours.
    func writeSleep(hours: Double, date: Date = Date()) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        let totalSeconds = Int(hours * 3600)
        let end = date
        let start = end.addingTimeInterval(TimeInterval(-totalSeconds))

        let metadata = ["SyncSource": "Google Health"]

        deleteExistingSamples(for: sleepType, date: date, metadataKey: "SyncSource") {
            let sample = HKCategorySample(
                type: sleepType,
                value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                start: start,
                end: end,
                metadata: metadata
            )

            self.healthStore.save(sample) { success, error in
                if !success {
                    print("Error saving sleep data: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }

    // MARK: - Write Calories
    
    /// Writes calorie data to HealthKit.
    func writeCalories(_ calories: Int, date: Date = Date()) {
        guard let calType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }

        let metadata = ["SyncSource": "Google Health"]

        deleteExistingSamples(for: calType, date: date, metadataKey: "SyncSource") {
            let quantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: Double(calories))
            let sample = HKQuantitySample(type: calType, quantity: quantity, start: date, end: date, metadata: metadata)

            self.healthStore.save(sample) { success, error in
                if !success {
                    print("Error saving calories: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }

    // MARK: - Delete Existing Synced Samples
    
    /// Deletes samples previously written by SyncMyFit on the same date to avoid duplication.
    ///
    /// - Parameters:
    ///   - type: The sample type to delete.
    ///   - date: The target date to search within.
    ///   - metadataKey: The metadata key used to identify the app’s previous samples.
    ///   - completion: A closure called once deletion completes.
    private func deleteExistingSamples(for type: HKSampleType, date: Date, metadataKey: String, completion: @escaping () -> Void) {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? date

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, results, error in
            let toDelete = results?.filter { $0.metadata?[metadataKey] as? String == "Google Health" } ?? []

            self.healthStore.delete(toDelete) { success, error in
                if let error = error {
                    print("Failed to delete old samples: \(error.localizedDescription)")
                }
                completion()
            }
        }

        healthStore.execute(query)
    }
}
