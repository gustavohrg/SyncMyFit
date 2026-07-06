//
//  AccountView.swift
//  SyncMyFit
//
//  Created by Baranidharan Pasupathi on 2025-07-12.
//

import SwiftUI

// MARK: - AccountView

/// Displays the user's Google profile, last sync time, and logout option with confirmation and loading feedback.
struct AccountView: View {

    // MARK: - Environment & State

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState

    @State private var userInfo: [String: Any] = [:]
    @State private var isLoading = true
    @State private var profileImageURL: URL?

    @State private var showLogoutConfirm = false
    @State private var isSigningOut = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if isLoading {
                    ProgressView("Loading...").padding()
                } else {
                    profileSection
                    Spacer()
                    logoutButton
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { withAnimation { dismiss() } }) {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .foregroundStyle(Color.syncDestructive)
                    }
                }
            }
            .onAppear(perform: loadDataIfNeeded)
            .alert("Are you sure you want to sign out?", isPresented: $showLogoutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    handleLogout()
                }
            }
            .overlay {
                if isSigningOut {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Signing out...")
                                .foregroundColor(.gray)
                                .font(.footnote)
                        }
                        .padding(24)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(radius: 10)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        VStack(spacing: 12) {
            // Avatar
            if let url = profileImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().frame(width: 100, height: 100)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                    case .failure:
                        fallbackAvatar
                    @unknown default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }

            // Display Name
            if let name = userInfo["displayName"] as? String {
                Text(name)
                    .font(.title2)
                    .bold()
            }

            // User ID
            if let encodedId = userInfo["encodedId"] as? String {
                Text("ID: \(encodedId)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Last Sync
            if let lastSync = SyncStatusManager.shared.lastSynced {
                Text("Last Synced: \(formatted(date: lastSync))")
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
        }
    }

    // MARK: - Logout Button

    private var logoutButton: some View {
        Button(action: {
            showLogoutConfirm = true
        }) {
            Text("Sign Out")
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.syncDestructive)
                .cornerRadius(12)
        }
        .padding(.horizontal)
    }

    // MARK: - Logout Handling

    /// Handles logout confirmation and transition with delay and loading overlay.
    private func handleLogout() {
        withAnimation {
            isSigningOut = true
        }

        // Simulate brief delay for UX polish
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            appState.logout()
            isSigningOut = false
        }
    }

    // MARK: - User Info Loading

    private func loadDataIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            self.userInfo = [
                "displayName": "Barani P",
                "encodedId": "B555",
                "lastSync": Date().addingTimeInterval(-3600)
            ]
            self.isLoading = false
            return
        }
        #endif

        fetchUserDetails()
    }

    private func fetchUserDetails() {
        isLoading = true
        let url = URL(string: "https://people.googleapis.com/v1/people/me?personFields=names,photos")!
        let request = URLRequest(url: url)

        GoogleHealthAuthManager.shared.performAuthenticatedRequest(request) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let data):
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Parse Google People API response
                        if let names = json["names"] as? [[String: Any]],
                           let primaryName = names.first(where: { ($0["metadata"] as? [String: Any])?["primary"] as? Bool == true })
                            ?? names.first,
                           let displayName = primaryName["displayName"] as? String {
                            self.userInfo["displayName"] = displayName
                        }

                        if let photos = json["photos"] as? [[String: Any]],
                           let primaryPhoto = photos.first(where: { ($0["metadata"] as? [String: Any])?["primary"] as? Bool == true })
                            ?? photos.first,
                           let photoURL = primaryPhoto["url"] as? String {
                            self.profileImageURL = URL(string: photoURL)
                        }

                        // Use resourceName as fallback ID
                        if let resourceName = json["resourceName"] as? String {
                            self.userInfo["encodedId"] = resourceName
                        }
                    }
                case .failure:
                    break
                }
            }
        }
    }

    // MARK: - Utilities

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var fallbackAvatar: some View {
        let name = (userInfo["displayName"] as? String) ?? "?"
        let initial = name.first.map { String($0).uppercased() } ?? "?"

        return ZStack {
            Circle()
                .fill(Color.color(for: name))
                .frame(width: 100, height: 100)
            Text(initial)
                .font(.system(size: 50, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Color Avatar Helper

extension Color {
    /// Generates a repeatable color based on a string input (e.g., name hash).
    static func color(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .yellow]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - Preview

#Preview {
    AccountView()
        .environmentObject(AppState())
}
