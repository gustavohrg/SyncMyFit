//
//  SyncController.swift
//  SyncMyFit
//
//  Handles fetching health data from Google Health API and writing to Apple HealthKit.
//  Supports steps, heart rate, sleep, and calorie sync operations.
//

import Foundation

// MARK: - SyncController

/// Handles the fetching of health data from Google Health API and writing to Apple HealthKit.
class SyncController {

    // MARK: - Singleton

    /// Shared instance for centralized sync handling.
    static let shared = SyncController()

    private let client = GoogleHealthClient.shared

    // MARK: - User Profile

    /// Fetches the user's display name from Google People API.
    func fetchUserProfile(completion: @escaping (Result<String, Error>) -> Void) {
        client.fetchProfile(completion: completion)
    }

    // MARK: - Step Sync

    /// Fetches today's step count from Google Health API.
    func fetchTodaySteps(completion: @escaping (Result<Int, Error>) -> Void) {
        client.fetchTodaySteps(completion: completion)
    }

    // MARK: - Heart Rate Sync

    /// Fetches today's heart rate data from Google Health API.
    func fetchHeartRateData(completion: @escaping (Result<[Int], Error>) -> Void) {
        client.fetchTodayHeartRate(completion: completion)
    }

    // MARK: - Sleep Sync

    /// Fetches today's sleep data from Google Health API.
    func fetchSleepData(completion: @escaping (Result<Double, Error>) -> Void) {
        client.fetchTodaySleep(completion: completion)
    }

    // MARK: - Calories Sync

    /// Fetches today's calories burned from Google Health API.
    func fetchCalories(completion: @escaping (Result<Int, Error>) -> Void) {
        client.fetchTodayCalories(completion: completion)
    }

    // MARK: - HealthKit Writing

    /// Writes collected health data to Apple HealthKit using HealthKitManager.
    func writeStepsToHealthKit(steps: Int, heartRates: [Int]? = nil, sleepHours: Double? = nil, calories: Int? = nil) {
        HealthKitManager.shared.writeSteps(steps)
        if let rates = heartRates {
            HealthKitManager.shared.writeHeartRates(rates)
        }
        if let hours = sleepHours {
            HealthKitManager.shared.writeSleep(hours: hours)
        }
        if let kcal = calories {
            HealthKitManager.shared.writeCalories(kcal)
        }
    }

    // MARK: - Bulk Sync Orchestration

    /// Coordinates the full sync of all health data types from Google Health to HealthKit.
    func syncAllData(completion: @escaping (Result<Void, Error>) -> Void) {
        let group = DispatchGroup()
        var syncError: Error?

        var steps: Int?
        var heartRates: [Int]?
        var sleepHours: Double?
        var calories: Int?

        group.enter()
        fetchTodaySteps {
            if case .success(let val) = $0 { steps = val }
            else if case .failure(let err) = $0 { syncError = err }
            group.leave()
        }

        group.enter()
        fetchHeartRateData {
            if case .success(let val) = $0 { heartRates = val }
            else if case .failure(let err) = $0 { syncError = err }
            group.leave()
        }

        group.enter()
        fetchSleepData {
            if case .success(let val) = $0 { sleepHours = val }
            else if case .failure(let err) = $0 { syncError = err }
            group.leave()
        }

        group.enter()
        fetchCalories {
            if case .success(let val) = $0 { calories = val }
            else if case .failure(let err) = $0 { syncError = err }
            group.leave()
        }

        group.notify(queue: .main) {
            if let error = syncError {
                completion(.failure(error))
            } else if let s = steps {
                self.writeStepsToHealthKit(steps: s, heartRates: heartRates, sleepHours: sleepHours, calories: calories)
                completion(.success(()))
            } else {
                completion(.failure(NSError(domain: "Missing required data", code: -3)))
            }
        }
    }
}
