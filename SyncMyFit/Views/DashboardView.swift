//
//  DashboardView.swift
//  SyncMyFit
//
//  Created by Baranidharan Pasupathi on 2025-06-30.
//

import SwiftUI

// MARK: - DashboardView

/// The main view that shows the user's synced Fitbit data and allows syncing to Apple Health.
struct DashboardView: View {

    // MARK: - Environment & State

    @EnvironmentObject var appState: AppState
    @StateObject private var syncStatus = SyncStatusManager.shared

    @State private var steps: Int?
    @State private var heartRates: [Int]?
    @State private var sleepHours: Double?
    @State private var caloriesBurned: Int?
    @State private var userName: String?

    @State private var showAccount = false
    @State private var isSyncing = false
    @State private var isDataLoaded = false

    // MARK: - View Body

    var body: some View {
        Group {
            if isDataLoaded {
                loadedDashboard
            } else {
                ProgressView("Loading your health data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: loadData)
        .sheet(isPresented: $showAccount) {
            AccountView().environmentObject(appState)
        }
    }

    // MARK: - Dashboard View

    private var loadedDashboard: some View {
        VStack {
            headerView

            if let fullName = userName {
                let name = fullName.components(separatedBy: " ").first ?? fullName
                Text("👋 Welcome, \(name)!")
                    .font(.title)
                    .bold()
                    .padding(.top, 12)

                Text("Ready to Sync?")
                    .font(.caption)
                    .padding(.top, 3)
            }

            Text("Here's your health snapshot for today 📊")
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding(.top, 48)

            Spacer()

            healthMetricsGrid
                .frame(maxHeight: 350)

            Spacer()

            footerView
        }
        .padding()
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Spacer()
            Button {
                withAnimation { showAccount = true }
            } label: {
                ZStack {
                    Circle().fill(.white).frame(width: 30, height: 30)
                    Circle().stroke(Color.syncPrimary, lineWidth: 3).frame(width: 30, height: 30)
                    Image(systemName: "person.fill")
                        .resizable()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 1.0, green: 0.4, blue: 0.4),
                                    Color(red: 0.8, green: 0.1, blue: 0.1)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .clipShape(Circle())
            }
        }
    }

    // MARK: - Health Metrics Grid

    private var healthMetricsGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 20)], spacing: 20) {
                if let sleep = sleepHours {
                    healthMetricView(title: "Sleep", value: formattedSleep(sleep), color: .metricSleep)
                }
                if let hr = heartRates, let min = hr.min(), let max = hr.max() {
                    healthMetricView(title: "Heart Rate", value: "\(min)-\(max)", color: .metricHeartRate)
                }
                if let steps = steps {
                    healthMetricView(title: "Steps", value: "\(steps)", color: .metricSteps)
                }
                if let calories = caloriesBurned {
                    healthMetricView(title: "Calories", value: "\(calories)", color: .metricCalories)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 24) {
            if let last = syncStatus.lastSynced {
                Text("Last synced: \(formatted(date: last))")
                    .foregroundColor(syncStatus.syncResult == .failure ? Color.syncDestructive : .gray)
                    .font(.footnote)
                    .transition(.opacity)
            }

            Button(action: startSync) {
                ZStack {
                    Circle()
                        .fill(Color.syncPrimary)
                        .frame(width: 64, height: 64)
                        .shadow(radius: 4)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    syncStatus.syncResult == .success ? .green :
                                        (syncStatus.syncResult == .failure ? Color.syncDestructive : .clear),
                                    lineWidth: 3
                                )
                        )

                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.white)
                        .font(.system(size: 26))
                        .rotationEffect(isSyncing ? .degrees(360) : .degrees(0))
                        .animation(isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isSyncing)
                }
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Sync Action

    private func startSync() {
        isSyncing = true

        SyncController.shared.syncAllData { result in
            DispatchQueue.main.async {
                isSyncing = false
                if case .success = result {
                    syncStatus.updateSyncResult(success: true)
                    SyncController.shared.fetchTodaySteps {
                        if case let .success(val) = $0 {
                            self.steps = val
                        }
                    }
                } else {
                    syncStatus.updateSyncResult(success: false)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        isDataLoaded = false
        
        // For preview/dummy mode fallback
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            self.userName = "Barani P"
            self.steps = 5555
            self.heartRates = [65, 78, 84]
            self.sleepHours = 8.5
            self.caloriesBurned = 2345
            self.syncStatus.lastSynced = Date()
            self.isDataLoaded = true
            return
        }
        #endif

        // Use a dispatch group to track all async tasks
        let group = DispatchGroup()

        group.enter()
        SyncController.shared.fetchUserProfile {
            if case let .success(name) = $0 { self.userName = name }
            group.leave()
        }

        group.enter()
        SyncController.shared.fetchTodaySteps {
            if case let .success(val) = $0 { self.steps = val }
            group.leave()
        }

        group.enter()
        SyncController.shared.fetchHeartRateData {
            if case let .success(val) = $0 { self.heartRates = val }
            group.leave()
        }

        group.enter()
        SyncController.shared.fetchSleepData {
            if case let .success(hours) = $0 {
                self.sleepHours = hours
            }
            group.leave()
        }

        group.enter()
        SyncController.shared.fetchCalories {
            if case let .success(val) = $0 { self.caloriesBurned = val }
            group.leave()
        }

        if let last = UserDefaults.standard.object(forKey: "last_sync_time") as? Date {
            syncStatus.lastSynced = last
        }

        group.notify(queue: .main) {
            self.isDataLoaded = true
        }
    }

    // MARK: - Utilities

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formattedSleep(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    private func healthMetricView(title: String, value: String, color: Color) -> some View {
        VStack {
            Circle()
                .fill(color.opacity(0.1))
                .frame(width: 80, height: 80)
                .overlay(
                    Text(value)
                        .font(.headline)
                )
            Text(title)
                .font(.caption)
        }
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
        .environmentObject(AppState())
}
