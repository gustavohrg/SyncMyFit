//
//  SyncController.swift
//  SyncMyFit
//
//  Created by Baranidharan Pasupathi on 2025-06-30.
//

import Foundation

// MARK: - SyncController

/// Handles the fetching of Fitbit data and writing to Apple HealthKit.
/// Supports steps, heart rate, sleep, and calorie sync operations.
class SyncController {
    
    // MARK: - Singleton
    
    /// Shared instance for centralized sync handling.
    static let shared = SyncController()

    // MARK: - User Profile
    
    /// Fetches the Fitbit user profile to retrieve display name.
    func fetchUserProfile(completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "https://api.fitbit.com/1/user/-/profile.json")!
        let request = URLRequest(url: url)

        GoogleHealthAuthManager.shared.performAuthenticatedRequest(request) { result in
            switch result {
            case .success(let data):
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let user = json["user"] as? [String: Any],
                       let name = user["displayName"] as? String {
                        completion(.success(name))
                    } else {
                        completion(.failure(NSError(domain: "Unexpected response", code: -2)))
                    }
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Step Sync
    
    /// Fetches today's step count from Fitbit.
    func fetchTodaySteps(completion: @escaping (Result<Int, Error>) -> Void) {
        let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let url = URL(string: "https://api.fitbit.com/1/user/-/activities/date/\(date).json")!
        let request = URLRequest(url: url)

        GoogleHealthAuthManager.shared.performAuthenticatedRequest(request) { result in
            switch result {
            case .success(let data):
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let summary = json["summary"] as? [String: Any],
                       let steps = summary["steps"] as? Int {
                        completion(.success(steps))
                    } else {
                        completion(.failure(NSError(domain: "Unexpected response", code: -2)))
                    }
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Heart Rate Sync

    /// Fetches today's minute-level heart rate data from Fitbit.
    func fetchHeartRateData(completion: @escaping (Result<[Int], Error>) -> Void) {
        let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let url = URL(string: "https://api.fitbit.com/1/user/-/activities/heart/date/\(date)/1d/1min.json")!
        let request = URLRequest(url: url)

        GoogleHealthAuthManager.shared.performAuthenticatedRequest(request) { result in
            switch result {
            case .success(let data):
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let activities = json["activities-heart-intraday"] as? [String: Any],
                       let dataset = activities["dataset"] as? [[String: Any]] {

                        let values = dataset.compactMap { $0["value"] as? Int }
                        completion(.success(values))
                    } else {
                        completion(.failure(NSError(domain: "Unexpected HR response", code: -2)))
                    }
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Sleep Sync

    /// Fetches sleep data for the current date from Fitbit.
    func fetchSleepData(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let url = URL(string: "https://api.fitbit.com/1.2/user/-/sleep/date/\(date).json")!
        let request = URLRequest(url: url)

        GoogleHealthAuthManager.shared.performAuthenticatedRequest(request) { result in
            switch result {
            case .success(let data):
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        completion(.success(json))
                    } else {
                        completion(.failure(NSError(domain: "Unexpected sleep response", code: -2)))
                    }
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Calories Sync

    /// Fetches calories burned for the current date from Fitbit.
    func fetchCalories(completion: @escaping (Result<Int, Error>) -> Void) {
        let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let url = URL(string: "https://api.fitbit.com/1/user/-/activities/date/\(date).json")!
        let request = URLRequest(url: url)

        GoogleHealthAuthManager.shared.performAuthenticatedRequest(request) { result in
            switch result {
            case .success(let data):
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let summary = json["summary"] as? [String: Any],
                       let calories = summary["caloriesOut"] as? Int {
                        completion(.success(calories))
                    } else {
                        completion(.failure(NSError(domain: "Unexpected calories response", code: -2)))
                    }
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
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

    /// Coordinates the full sync of all health data types from Fitbit to HealthKit.
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
            if case .success(let json) = $0,
               let sleepArray = json["sleep"] as? [[String: Any]],
               let summary = sleepArray.first,
               let duration = summary["duration"] as? Double {
                sleepHours = duration / 3600000.0  // Fitbit returns duration in ms
            } else if case .failure(let err) = $0 {
                syncError = err
            }
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
