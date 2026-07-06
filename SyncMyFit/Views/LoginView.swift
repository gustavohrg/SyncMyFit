//
//  LoginView.swift
//  SyncMyFit
//
//  Created by Baranidharan Pasupathi on 2025-06-30.
//

import SwiftUI

// MARK: - LoginView

/// The initial view shown to the user.
/// Displays branding and handles login via Google OAuth.
struct LoginView: View {
    
    // MARK: - Environment & State
    
    @EnvironmentObject var appState: AppState
    @State private var showError = false
    @State private var errorMessage = ""

    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 24) {
            logoView
                .padding(.bottom, 25)
            
            Text("SyncMyFit")
                .font(.largeTitle)
                .bold()
            
            Text("Sync your Google Health data with Apple Health")
                .multilineTextAlignment(.center)
                .foregroundStyle(.gray)
                .padding(.horizontal)
            
            Button(action: {
                startLoginFlow()
            }) {
                Text("Sign in with Google")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.syncPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding()
        .alert("Login Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Logo View

    /// Displays combined Google-colored dots and Apple Health heart icon.
    private var logoView: some View {
        ZStack {
            // Apple Health-style heart
            Image(systemName: "heart.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 125, height: 125)
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

            // Google-colored rhombus pattern of dots
            Group {
                // Row 1
                dot(x: 0, y: -18, color: .blue)

                // Row 2
                dot(x: -6, y: -12, color: .red)
                dot(x: 6, y: -12, color: .yellow)

                // Row 3
                dot(x: -12, y: -6, color: .green)
                dot(x: 0, y: -6, color: .blue)
                dot(x: 12, y: -6, color: .red)

                // Row 4
                dot(x: -18, y: 0, color: .yellow)
                dot(x: -6, y: 0, color: .green)
                dot(x: 6, y: 0, color: .blue)
                dot(x: 18, y: 0, color: .red)

                // Row 5
                dot(x: -12, y: 6, color: .yellow)
                dot(x: 0, y: 6, color: .green)
                dot(x: 12, y: 6, color: .blue)

                // Row 6
                dot(x: -6, y: 12, color: .red)
                dot(x: 6, y: 12, color: .yellow)

                // Row 7
                dot(x: 0, y: 18, color: .green)
            }
        }
    }

    // MARK: - Google Login Flow

    /// Initiates the login process using Google OAuth and updates app state on success.
    private func startLoginFlow() {
        GoogleHealthAuthManager.shared.startLogin { result in
            switch result {
            case .success(let code):
                GoogleHealthAuthManager.shared.fetchAccessToken(authCode: code) { tokenResult in
                    switch tokenResult {
                    case .success:
                        DispatchQueue.main.async {
                            appState.loginSuccessful()
                        }
                    case .failure(let error):
                        DispatchQueue.main.async {
                            showError = true
                            errorMessage = "Token fetch failed: \(error.localizedDescription)"
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    showError = true
                    errorMessage = "Login failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Dot Helper

    /// Builds a rotated square used to mimic Google-colored dot.
    @ViewBuilder
    private func dot(x: CGFloat, y: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .frame(width: 5, height: 5)
            .rotationEffect(.degrees(45))
            .offset(x: x, y: y)
            .foregroundStyle(color)
    }
}

// MARK: - Preview

#Preview {
    LoginView()
}
