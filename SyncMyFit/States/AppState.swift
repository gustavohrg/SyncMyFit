//
//  AppState.swift
//  SyncMyFit
//
//  Created by Baranidharan Pasupathi on 2025-07-08.
//

import Foundation
import Combine

// MARK: - AppState

/// Global app state observable object used for managing login state and authentication transitions.
class AppState: ObservableObject {

    // MARK: - Published Properties

    /// Indicates whether the user is currently logged in.
    @Published var isLoggedIn: Bool = false

    /// Indicates whether the app is currently checking login state (to suppress premature view rendering).
    @Published var isCheckingAuth: Bool = true

    // MARK: - Login State Check

    /// Checks the current login state based on stored access token and its validity.
    /// Displays a loading screen until the check completes.
    func checkLoginState() {
        isCheckingAuth = true

        if let _ = GoogleHealthAuthManager.shared.storedAccessToken {
            if GoogleHealthAuthManager.shared.isTokenValid() {
                isLoggedIn = true
                isCheckingAuth = false
            } else {
                // Attempt to refresh token if expired
                GoogleHealthAuthManager.shared.refreshAccessToken { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            self.isLoggedIn = true
                        case .failure:
                            self.logout()
                        }
                        self.isCheckingAuth = false
                    }
                }
            }
        } else {
            isLoggedIn = false
            isCheckingAuth = false
        }
    }

    // MARK: - Logout

    /// Clears tokens and resets login state.
    func logout() {
        GoogleHealthAuthManager.shared.logout()
        isLoggedIn = false
    }

    // MARK: - Successful Login

    /// Called after a successful login to update state.
    func loginSuccessful() {
        isLoggedIn = true
    }
}
