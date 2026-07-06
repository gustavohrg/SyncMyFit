//
//  SyncMyFitApp.swift
//  SyncMyFit
//
//  Created by Baranidharan Pasupathi on 2025-06-24.
//

import SwiftUI
import AuthenticationServices

// MARK: - Entry Point

@main
struct SyncMyFitApp: App {

    // MARK: - Properties

    /// Holds the global application state (e.g., login status)
    @StateObject private var appState = AppState()

    // MARK: - Initializer

    init() {
        // Request authorization to read/write to Apple HealthKit
        HealthKitManager.shared.requestAuthorization { success, error in
            if !success {
                print("HealthKit authorization failed: \(String(describing: error))")
            }
        }
    }

    // MARK: - Scene Body

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if appState.isCheckingAuth {
                    // Show neutral loading screen while auth is being verified
                    ProgressView("Checking login...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appState.isLoggedIn {
                    // Show Dashboard if user is authenticated
                    DashboardView()
                        .environmentObject(appState)
                } else {
                    // Show LoginView if user is not logged in
                    LoginView()
                        .environmentObject(appState)
                }
            }
            .onAppear {
                // Check login state when app launches
                appState.checkLoginState()
            }
            .onOpenURL { url in
                // Handle redirect from Google OAuth flow
                GoogleHealthAuthManager.shared.handleRedirectURL(url)
            }
        }
    }
}
