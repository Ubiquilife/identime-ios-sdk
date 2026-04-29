import Foundation
import UIKit

/// IdentiMe authentication SDK for iOS.
///
/// Provides OAuth2 authentication via IdentiMe for any iOS app.
/// No Ubiquilife dependencies required.
///
/// ## Usage
///
/// ```swift
/// // 1. Configure
/// let auth = IdentiMeAuth(config: IdentiMeConfig(
///     clientId: "your-client-id",
///     clientSecret: "your-client-secret",
///     identimeURL: "https://identime.example.com",
///     redirectURI: "myapp://callback"
/// ))
///
/// // 2. Start login (opens IdentiMe app or browser)
/// auth.login()
///
/// // 3. Handle callback in your App's onOpenURL
/// auth.handleCallback(url: url) { result in
///     switch result {
///     case .success(let token):
///         // token.accessToken is your OAuth access token
///         // token.user contains the authenticated user profile
///     case .failure(let error):
///         print(error)
///     }
/// }
/// ```
public final class IdentiMeAuth: @unchecked Sendable {
    private let config: IdentiMeConfig
    private let session: URLSession
    private var pendingCompletion: ((Result<IdentiMeToken, IdentiMeError>) -> Void)?

    public init(config: IdentiMeConfig) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        sessionConfig.timeoutIntervalForResource = 60
        self.session = URLSession(
            configuration: sessionConfig,
            delegate: TrustAllDelegate(),
            delegateQueue: nil
        )
    }

    // MARK: - Login

    /// Opens IdentiMe to authenticate the user.
    /// Tries the IdentiMe app first via custom URL scheme,
    /// falls back to Safari if the app is not installed.
    @MainActor
    public func login() {
        var components = URLComponents(string: "identime://authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: ""),
        ]

        guard let url = components.url else { return }

        UIApplication.shared.open(url, options: [.universalLinksOnly: false]) { success in
            if !success {
                // IdentiMe app not installed, fall back to browser
                var browserComponents = URLComponents(string: "\(self.config.identimeURL)/oauth/authorize")!
                browserComponents.queryItems = [
                    URLQueryItem(name: "client_id", value: self.config.clientId),
                    URLQueryItem(name: "redirect_uri", value: self.config.redirectURI),
                    URLQueryItem(name: "response_type", value: "code"),
                    URLQueryItem(name: "scope", value: ""),
                ]
                if let browserURL = browserComponents.url {
                    UIApplication.shared.open(browserURL)
                }
            }
        }
    }

    // MARK: - Callback

    /// Handle the OAuth callback URL from IdentiMe.
    /// Call this from your App's `onOpenURL` handler.
    ///
    /// - Parameters:
    ///   - url: The callback URL received
    ///   - completion: Called with the authentication result
    public func handleCallback(url: URL, completion: @escaping @Sendable (Result<IdentiMeToken, IdentiMeError>) -> Void) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            let parsed = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let errorValue = parsed?.queryItems?.first(where: { $0.name == "error" })?.value {
                completion(.failure(.authorizationDenied(errorValue)))
            } else {
                completion(.failure(.noCodeReceived))
            }
            return
        }

        Task {
            do {
                let token = try await exchangeCode(code)
                await MainActor.run { completion(.success(token)) }
            } catch let error as IdentiMeError {
                await MainActor.run { completion(.failure(error)) }
            } catch {
                await MainActor.run { completion(.failure(.networkError(error))) }
            }
        }
    }

    /// Async version of handleCallback.
    public func handleCallback(url: URL) async throws -> IdentiMeToken {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw IdentiMeError.noCodeReceived
        }
        return try await exchangeCode(code)
    }

    // MARK: - Token Exchange

    /// Exchange an authorization code for an access token.
    private func exchangeCode(_ code: String) async throws -> IdentiMeToken {
        guard let url = URL(string: config.tokenURL) else {
            throw IdentiMeError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = [
            "grant_type": "authorization_code",
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
            "redirect_uri": config.redirectURI,
            "code": code,
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw IdentiMeError.invalidResponse
        }

        if http.statusCode >= 400 {
            if let errorBody = try? JSONDecoder().decode(OAuthError.self, from: data) {
                throw IdentiMeError.oauthError(errorBody.error, errorBody.error_description)
            }
            throw IdentiMeError.httpError(http.statusCode)
        }

        let oauthToken = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)

        // Fetch user profile
        let user = try await fetchUser(accessToken: oauthToken.access_token)

        return IdentiMeToken(
            accessToken: oauthToken.access_token,
            refreshToken: oauthToken.refresh_token,
            tokenType: oauthToken.token_type ?? "Bearer",
            expiresIn: oauthToken.expires_in,
            user: user
        )
    }

    /// Fetch the authenticated user's profile from IdentiMe.
    private func fetchUser(accessToken: String) async throws -> IdentiMeUser {
        guard let url = URL(string: "\(config.identimeURL)/api/me") else {
            throw IdentiMeError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw IdentiMeError.userFetchFailed
        }

        // IdentiMe returns {"data": [{...}]} or {"data": {...}}
        struct UserWrapper: Codable { let data: UserData }
        struct UserData: Codable {
            let id: String
            let first_name: String?
            let last_name: String?
            let display_name: String?
            let email: String?
            let slug: String?
            let timezone: String?
        }

        // Try array first, then single object
        if let wrapper = try? JSONDecoder().decode([String: [UserData]].self, from: data),
           let user = wrapper["data"]?.first {
            return IdentiMeUser(
                id: user.id,
                firstName: user.first_name,
                lastName: user.last_name,
                displayName: user.display_name,
                email: user.email,
                slug: user.slug,
                timezone: user.timezone
            )
        }

        if let wrapper = try? JSONDecoder().decode([String: UserData].self, from: data),
           let user = wrapper["data"] {
            return IdentiMeUser(
                id: user.id,
                firstName: user.first_name,
                lastName: user.last_name,
                displayName: user.display_name,
                email: user.email,
                slug: user.slug,
                timezone: user.timezone
            )
        }

        throw IdentiMeError.userFetchFailed
    }
}

// MARK: - TLS delegate for development

private final class TrustAllDelegate: NSObject, URLSessionDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host.hasSuffix(".test"),
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - Internal response types

private struct OAuthTokenResponse: Codable {
    let access_token: String
    let token_type: String?
    let expires_in: Int?
    let refresh_token: String?
}

private struct OAuthError: Codable {
    let error: String
    let error_description: String?
}
