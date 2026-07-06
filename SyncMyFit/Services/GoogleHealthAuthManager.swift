//
//  GoogleHealthAuthManager.swift
//  SyncMyFit
//
//  Created on migration from Fitbit Web API to Google Health API.
//

import Foundation
import AuthenticationServices
import UIKit

// MARK: - GoogleHealthAuthManager

/// Manages OAuth authentication with Google Health API using OAuth 2.0.
/// Handles authorization, token exchange, refresh, and secure token storage.
class GoogleHealthAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {

    // MARK: - Singleton

    static let shared = GoogleHealthAuthManager()

    // MARK: - Properties

    private let clientId = Secrets.shared.googleClientID
    private let clientSecret = Secrets.shared.googleClientSecret
    private var currentSession: ASWebAuthenticationSession?

    /// Redirect URI uses reversed client ID format (Google standard for iOS).
    private var redirectURI: String {
        "com.googleusercontent.apps.\(clientId.replacingOccurrences(of: ".", with: "-"))://"
    }

    /// OAuth scopes: health data + profile (display name + avatar via People API).
    private let scopes = [
        "https://www.googleapis.com/auth/googlehealth.activity_and_fitness",
        "https://www.googleapis.com/auth/userinfo.profile"
    ].joined(separator: " ")

    /// Exposes the stored access token publicly (read-only).
    var accessToken: String? {
        storedAccessToken
    }

    // MARK: - OAuth Login Flow

    /// Initiates Google OAuth flow using ASWebAuthenticationSession.
    func startLogin(completion: @escaping (Result<String, Error>) -> Void) {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let authURL = components.url else {
            completion(.failure(NSError(domain: "GoogleAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid auth URL"])))
            return
        }

        currentSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "com.googleusercontent.apps"
        ) { callbackURL, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let callbackURL = callbackURL,
                  let code = self.extractCode(from: callbackURL) else {
                completion(.failure(NSError(domain: "GoogleAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get authorization code"])))
                return
            }

            completion(.success(code))
        }

        currentSession?.presentationContextProvider = self
        currentSession?.prefersEphemeralWebBrowserSession = true
        currentSession?.start()
    }

    // MARK: - Token Exchange

    /// Exchanges the authorization code for access and refresh tokens.
    func fetchAccessToken(authCode: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "code": authCode,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                return completion(.failure(error))
            }

            guard let data = data else {
                return completion(.failure(NSError(domain: "No data", code: -1)))
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

                if let accessToken = json?["access_token"] as? String {
                    self.storedAccessToken = accessToken

                    if let refreshToken = json?["refresh_token"] as? String {
                        self.storedRefreshToken = refreshToken
                    }

                    if let expiresIn = json?["expires_in"] as? Double {
                        let expiresAt = Date().addingTimeInterval(expiresIn)
                        UserDefaults.standard.set(expiresAt, forKey: "google_token_expires_at")
                    }

                    completion(.success(accessToken))
                } else if let errorDescription = json?["error_description"] as? String {
                    completion(.failure(NSError(domain: "GoogleAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: errorDescription])))
                } else {
                    completion(.failure(NSError(domain: "Unexpected token response", code: -3)))
                }
            } catch {
                print("JSON parsing error: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Token Refresh

    /// Refreshes the Google access token using the stored refresh token.
    func refreshAccessToken(completion: @escaping (Result<String, Error>) -> Void) {
        guard let refreshToken = storedRefreshToken,
              let url = URL(string: "https://oauth2.googleapis.com/token") else {
            return completion(.failure(NSError(domain: "Missing refresh token", code: -1)))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                return completion(.failure(error))
            }

            guard let data = data else {
                return completion(.failure(NSError(domain: "No data", code: -1)))
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

                if let newAccessToken = json?["access_token"] as? String {
                    self.storedAccessToken = newAccessToken

                    if let expiresIn = json?["expires_in"] as? Double {
                        let expiresAt = Date().addingTimeInterval(expiresIn)
                        UserDefaults.standard.set(expiresAt, forKey: "google_token_expires_at")
                    }

                    completion(.success(newAccessToken))
                } else if let errorDescription = json?["error_description"] as? String {
                    completion(.failure(NSError(domain: "GoogleAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: errorDescription])))
                } else {
                    completion(.failure(NSError(domain: "Unexpected token response", code: -3)))
                }
            } catch {
                print("JSON parsing error: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Authorized Requests

    /// Sends a request with the current access token.
    /// Automatically refreshes token once if expired.
    func performAuthenticatedRequest(
        _ request: URLRequest,
        retryOnAuthFailure: Bool = true,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        var request = request

        guard let token = storedAccessToken else {
            return completion(.failure(NSError(domain: "No access token", code: 401)))
        }

        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                return completion(.failure(error))
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401, retryOnAuthFailure {
                self.refreshAccessToken { result in
                    switch result {
                    case .success:
                        self.performAuthenticatedRequest(request, retryOnAuthFailure: false, completion: completion)
                    case .failure(let refreshError):
                        completion(.failure(refreshError))
                    }
                }
            } else if let data = data {
                completion(.success(data))
            } else {
                completion(.failure(NSError(domain: "Unknown response", code: -1)))
            }
        }.resume()
    }

    // MARK: - Redirect Handler

    /// Handles the redirect URL and triggers token exchange.
    func handleRedirectURL(_ url: URL) {
        guard let code = extractCode(from: url) else {
            print("No authorization code in URL")
            return
        }

        print("Authorization Code: \(code)")
        fetchAccessToken(authCode: code) { result in
            switch result {
            case .success(let token): print("Access Token: \(token)")
            case .failure(let error): print("Token exchange failed: \(error)")
            }
        }
    }

    // MARK: - Presentation Anchor (ASWebAuthenticationSession)

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    // MARK: - Utility

    private func extractCode(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: true)?
            .queryItems?.first(where: { $0.name == "code" })?.value
    }

    func isTokenValid() -> Bool {
        guard let expiresAt = UserDefaults.standard.object(forKey: "google_token_expires_at") as? Date else {
            return false
        }
        return Date() < expiresAt
    }
}

// MARK: - Keychain Accessors

extension GoogleHealthAuthManager {
    private var accessTokenKey: String { "google_access_token" }
    private var refreshTokenKey: String { "google_refresh_token" }
    private var service: String { "com.syncmyfit.google_token" }

    var storedAccessToken: String? {
        get {
            guard let data = KeychainHelper.shared.read(service: service, account: accessTokenKey) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            if let token = newValue {
                KeychainHelper.shared.save(Data(token.utf8), service: service, account: accessTokenKey)
            } else {
                KeychainHelper.shared.delete(service: service, account: accessTokenKey)
            }
        }
    }

    var storedRefreshToken: String? {
        get {
            guard let data = KeychainHelper.shared.read(service: service, account: refreshTokenKey) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            if let token = newValue {
                KeychainHelper.shared.save(Data(token.utf8), service: service, account: refreshTokenKey)
            } else {
                KeychainHelper.shared.delete(service: service, account: refreshTokenKey)
            }
        }
    }

    /// Clears stored tokens from the Keychain.
    func logout() {
        storedAccessToken = nil
        storedRefreshToken = nil
        UserDefaults.standard.removeObject(forKey: "google_token_expires_at")
    }
}
