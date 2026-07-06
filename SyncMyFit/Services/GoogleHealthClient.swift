//
//  GoogleHealthClient.swift
//  SyncMyFit
//
//  Fetches health data from Google Health API.
//

import Foundation

// MARK: - GoogleHealthClient

/// Client for fetching health data from Google Health API (health.googleapis.com/v4).
class GoogleHealthClient {

    static let shared = GoogleHealthClient()

    private let baseURL = "https://health.googleapis.com/v4"
    private let peopleURL = "https://people.googleapis.com/v1"
    private let authManager = GoogleHealthAuthManager.shared

    private init() {}

    // MARK: - Fetch Steps

    /// Fetches step count data points for the given date range.
    func fetchSteps(since: Date, to: Date, completion: @escaping (Result<[HealthDataPoint], Error>) -> Void) {
        fetchDataPoints(dataType: "steps", since: since, to: to, completion: completion)
    }

    /// Fetches today's total step count.
    func fetchTodaySteps(completion: @escaping (Result<Int, Error>) -> Void) {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Date()

        fetchSteps(since: start, to: end) { result in
            switch result {
            case .success(let points):
                let total = points.reduce(0) { $0 + $1.stepsValue }
                completion(.success(total))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Fetch Heart Rate

    /// Fetches heart rate data points for the given date range.
    func fetchHeartRate(since: Date, to: Date, completion: @escaping (Result<[HealthDataPoint], Error>) -> Void) {
        fetchDataPoints(dataType: "heart-rate", since: since, to: to, completion: completion)
    }

    /// Fetches today's heart rate values (BPM list).
    func fetchTodayHeartRate(completion: @escaping (Result<[Int], Error>) -> Void) {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Date()

        fetchHeartRate(since: start, to: end) { result in
            switch result {
            case .success(let points):
                let bpmValues = points.map { $0.heartRateBPM }
                completion(.success(bpmValues))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Fetch Sleep

    /// Fetches sleep session data points for the given date range.
    func fetchSleep(since: Date, to: Date, completion: @escaping (Result<[HealthDataPoint], Error>) -> Void) {
        fetchDataPoints(dataType: "sleep", since: since, to: to, completion: completion)
    }

    /// Fetches today's total sleep hours.
    func fetchTodaySleep(completion: @escaping (Result<Double, Error>) -> Void) {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Date()

        fetchSleep(since: start, to: end) { result in
            switch result {
            case .success(let points):
                let totalHours = points.reduce(0) { $0 + $1.sleepHours }
                completion(.success(totalHours))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Fetch Calories

    /// Fetches active energy burned data points for the given date range.
    func fetchCalories(since: Date, to: Date, completion: @escaping (Result<[HealthDataPoint], Error>) -> Void) {
        fetchDataPoints(dataType: "active-energy-burned", since: since, to: to, completion: completion)
    }

    /// Fetches today's total calories burned.
    func fetchTodayCalories(completion: @escaping (Result<Int, Error>) -> Void) {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Date()

        fetchCalories(since: start, to: end) { result in
            switch result {
            case .success(let points):
                let total = points.reduce(0) { $0 + $1.caloriesValue }
                completion(.success(total))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Fetch Profile

    /// Fetches user display name from Google People API.
    func fetchProfile(completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "\(peopleURL)/people/me?personFields=names") else {
            return completion(.failure(NSError(domain: "Invalid URL", code: -1)))
        }

        let request = URLRequest(url: url)

        authManager.performAuthenticatedRequest(request) { result in
            switch result {
            case .success(let data):
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let names = json["names"] as? [[String: Any]],
                       let primaryName = names.first(where: {
                           ($0["metadata"] as? [String: Any])?["primary"] as? Bool == true
                       }) ?? names.first,
                       let displayName = primaryName["displayName"] as? String {
                        completion(.success(displayName))
                    } else {
                        completion(.failure(NSError(domain: "No name found", code: -2)))
                    }
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Private Helpers

    /// Generic fetch for data points of a given type.
    private func fetchDataPoints(
        dataType: String,
        since: Date,
        to: Date,
        completion: @escaping (Result<[HealthDataPoint], Error>) -> Void
    ) {
        let startStr = Self.isoFormatter.string(from: since)
        let endStr = Self.isoFormatter.string(from: to)

        guard let url = URL(string: "\(baseURL)/users/me/dataTypes/\(dataType)/dataPoints?startTime=\(startStr)&endTime=\(endStr)") else {
            return completion(.failure(NSError(domain: "Invalid URL", code: -1)))
        }

        let request = URLRequest(url: url)

        authManager.performAuthenticatedRequest(request) { result in
            switch result {
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(HealthDataResponse.self, from: data)
                    completion(.success(response.dataPoints ?? []))
                } catch {
                    print("Decode error for \(dataType): \(error)")
                    // Fallback: try raw JSON parsing
                    self.parseRawJSON(data, completion: completion)
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Fallback raw JSON parser when Codable fails.
    private func parseRawJSON(_ data: Data, completion: @escaping (Result<[HealthDataPoint], Error>) -> Void) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pointsArray = json["dataPoints"] as? [[String: Any]] else {
            return completion(.success([]))
        }

        var points: [HealthDataPoint] = []
        for dict in pointsArray {
            let point = HealthDataPoint(
                startTime: dict["startTime"] as? String,
                endTime: dict["endTime"] as? String,
                startUtcOffset: dict["startUtcOffset"] as? String,
                endUtcOffset: dict["endUtcOffset"] as? String,
                value: dict["value"] as? Double,
                intValues: dict["intValues"] as? [Int],
                bpm: dict["bpm"] as? Int,
                measurementLocation: dict["measurementLocation"] as? Int,
                sessionStart: dict["sessionStart"] as? String,
                sessionEnd: dict["sessionEnd"] as? String,
                sleepLevel: nil,
                dataSource: nil
            )
            points.append(point)
        }
        completion(.success(points))
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
