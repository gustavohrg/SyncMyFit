//
//  HealthDataPoint.swift
//  SyncMyFit
//
//  Data models for Google Health API response parsing.
//

import Foundation

// MARK: - HealthDataResponse

/// Top-level response from Google Health API list endpoint.
struct HealthDataResponse: Codable {
    let dataPoints: [HealthDataPoint]?
}

// MARK: - HealthDataPoint

/// Represents a single data point from the Google Health API.
/// Fields are optional because different data types return different subsets.
struct HealthDataPoint: Codable {
    let startTime: String?
    let endTime: String?
    let startUtcOffset: String?
    let endUtcOffset: String?

    // Interval types (steps, active-energy-burned)
    let value: Double?
    let intValues: [Int]?

    // Sample types (heart-rate)
    let bpm: Int?
    let measurementLocation: Int?

    // Session types (sleep)
    let sessionStart: String?
    let sessionEnd: String?
    let sleepLevel: [SleepLevel]?

    // Common
    let dataSource: DataSource?
}

// MARK: - SleepLevel

struct SleepLevel: Codable {
    let level: String?
    let count: Int?
    let startTime: String?
    let endTime: String?
}

// MARK: - DataSource

struct DataSource: Codable {
    let dataSourceId: String?
    let type: String?
    let device: Device?
}

// MARK: - Device

struct Device: Codable {
    let deviceType: String?
    let manufacturer: String?
    let model: String?
}

// MARK: - Helper Extensions

extension HealthDataPoint {
    /// Parse ISO 8601 start time to Date.
    var startDate: Date? {
        guard let time = startTime ?? sessionStart else { return nil }
        return Self.isoFormatter.date(from: time)
    }

    /// Parse ISO 8601 end time to Date.
    var endDate: Date? {
        guard let time = endTime ?? sessionEnd else { return nil }
        return Self.isoFormatter.date(from: time)
    }

    /// Steps value (for interval type).
    var stepsValue: Int {
        if let v = value { return Int(v) }
        if let ints = intValues, let first = ints.first { return first }
        return 0
    }

    /// BPM value (for heart-rate sample type).
    var heartRateBPM: Int {
        return bpm ?? Int(value ?? 0)
    }

    /// Duration in hours (for sleep session type).
    var sleepHours: Double {
        guard let start = startDate, let end = endDate else { return 0 }
        return end.timeIntervalSince(start) / 3600.0
    }

    /// Calories value (for active-energy-burned interval type).
    var caloriesValue: Int {
        if let v = value { return Int(v) }
        return 0
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
