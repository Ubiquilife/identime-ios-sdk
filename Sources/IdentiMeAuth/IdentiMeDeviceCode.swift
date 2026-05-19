//
// IdentiMeDeviceCode.swift
//
// OAuth 2.0 Device Authorization Grant (RFC 8628) against IdentiMe.
// Public-client + PKCE-augmented. Designed for desktop and other
// contexts where the standard redirect-callback flow is awkward —
// the user verifies on any browser, the app polls until approved.
//
// Lifecycle:
//
//   1. POST /oauth/device/code → device_code + user_code + verification_uri
//   2. Caller opens the verification URL in the user's default browser.
//   3. Poll /oauth/token (grant_type = urn:ietf:params:oauth:grant-type:
//      device_code) with device_code + code_verifier. Server returns
//      `authorization_pending` until the user approves; we back off per
//      the `interval` hint.
//   4. On success the call returns an IdentiMeToken; the caller
//      persists it (typically in Keychain) and proceeds to the host
//      app's session bootstrap.
//
// Why a separate module from IdentiMeAuth (the redirect-callback flow):
// device-code is multiplatform with no UI dependency. It works
// identically on macOS, Linux, headless CI, and any embedded surface.
// IdentiMeAuth's redirect flow needs UIApplication/NSWorkspace to
// punch through to the IdentiMe app or browser.
//

import Foundation
import CryptoKit
import Security

/// Driver for the OAuth 2.0 Device Authorization Grant. Multiplatform
/// (iOS / macOS); no UIKit or AppKit dependency.
@available(iOS 16, macOS 13, *)
public final class IdentiMeDeviceCode: @unchecked Sendable {
    private let config: IdentiMeConfig
    private let session: URLSession

    public init(config: IdentiMeConfig,
                session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Drive the device-code flow to completion.
    ///
    /// - Parameters:
    ///   - scope: Space-separated OAuth scope string. Default empty.
    ///   - onAwaitingApproval: Called once with the user_code and
    ///     verification URL so the caller can present them (open the
    ///     browser, render the code in a SwiftUI sheet, etc).
    /// - Returns: An IdentiMeToken once the user has approved.
    public func signIn(
        scope: String = "",
        onAwaitingApproval: @Sendable (DeviceFlowApproval) async -> Void
    ) async throws -> IdentiMeToken {
        let verifier = PKCE.generateVerifier()
        let challenge = PKCE.challenge(from: verifier)

        let device = try await requestDeviceCode(scope: scope, challenge: challenge)
        await onAwaitingApproval(DeviceFlowApproval(
            userCode: device.userCode,
            verificationURI: device.verificationURI,
            verificationURIComplete: device.verificationURIComplete
        ))

        return try await pollForToken(deviceCode: device.deviceCode,
                                      verifier: verifier,
                                      interval: device.interval,
                                      expiresIn: device.expiresIn)
    }

    /// Exchange a refresh token for a fresh access token. Throws
    /// `.refreshFailed` if the refresh token has been revoked.
    public func refresh(using refreshToken: String) async throws -> IdentiMeToken {
        guard let url = URL(string: "\(config.identimeURL)/oauth/token") else {
            throw IdentiMeError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientId,
        ])

        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try parseTokenResponse(data, fallbackRefreshToken: refreshToken)
    }

    // MARK: - Internals

    private func requestDeviceCode(scope: String, challenge: String) async throws -> DeviceCodeResponse {
        guard let url = URL(string: "\(config.identimeURL)/oauth/device/code") else {
            throw IdentiMeError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody([
            "client_id": config.clientId,
            "scope": scope,
            "code_challenge": challenge,
            "code_challenge_method": "S256",
        ])

        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }

    private func pollForToken(deviceCode: String,
                              verifier: String,
                              interval: TimeInterval,
                              expiresIn: TimeInterval) async throws -> IdentiMeToken {
        guard let url = URL(string: "\(config.identimeURL)/oauth/token") else {
            throw IdentiMeError.invalidURL
        }
        let deadline = Date().addingTimeInterval(expiresIn)
        var currentInterval = max(1, interval)

        while Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(currentInterval * 1_000_000_000))
            if Task.isCancelled { throw CancellationError() }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = formBody([
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "device_code": deviceCode,
                "client_id": config.clientId,
                "code_verifier": verifier,
            ])

            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            if let http, (200..<300).contains(http.statusCode) {
                return try parseTokenResponse(data, fallbackRefreshToken: nil)
            }

            if let errorDoc = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
                switch errorDoc.error {
                case "authorization_pending":
                    continue
                case "slow_down":
                    currentInterval += 5
                    continue
                case "expired_token":
                    throw IdentiMeError.deviceCodeExpired
                case "access_denied":
                    throw IdentiMeError.authorizationDenied(errorDoc.error)
                default:
                    throw IdentiMeError.networkError(NSError(
                        domain: "IdentiMeDeviceCode",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: errorDoc.errorDescription ?? errorDoc.error]
                    ))
                }
            }
            throw IdentiMeError.networkError(NSError(
                domain: "IdentiMeDeviceCode",
                code: http?.statusCode ?? -1
            ))
        }
        throw IdentiMeError.deviceCodeExpired
    }

    private func parseTokenResponse(_ data: Data, fallbackRefreshToken: String?) throws -> IdentiMeToken {
        let decoder = JSONDecoder()
        let raw = try decoder.decode(TokenWireFormat.self, from: data)
        return IdentiMeToken(
            accessToken: raw.accessToken,
            refreshToken: raw.refreshToken ?? fallbackRefreshToken,
            tokenType: raw.tokenType ?? "Bearer",
            expiresIn: raw.expiresIn,
            scope: raw.scope,
            user: nil
        )
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw IdentiMeError.networkError(NSError(domain: "IdentiMeDeviceCode", code: -1))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw IdentiMeError.networkError(NSError(domain: "IdentiMeDeviceCode", code: http.statusCode))
        }
    }

    private func formBody(_ params: [String: String]) -> Data {
        let encoded = params.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return "\(key)=\(v)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }
}

// MARK: - Public payload types

/// Progress object surfaced to the caller while the user is approving
/// the device-code in their browser.
public struct DeviceFlowApproval: Sendable {
    public let userCode: String
    public let verificationURI: URL
    public let verificationURIComplete: URL

    public init(userCode: String, verificationURI: URL, verificationURIComplete: URL) {
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.verificationURIComplete = verificationURIComplete
    }
}

// MARK: - PKCE (RFC 7636) — multiplatform, no UI dep

public enum PKCE {
    /// High-entropy code verifier (43-128 chars of the unreserved
    /// alphabet per RFC 7636).
    public static func generateVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString + UUID().uuidString
        }
        return base64URLEncode(Data(bytes))
    }

    public static func challenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(hash))
    }

    public static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Wire types

private struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let verificationURIComplete: URL
    let interval: TimeInterval
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete"
        case interval
        case expiresIn = "expires_in"
    }
}

private struct TokenWireFormat: Decodable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: TimeInterval
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }
}

private struct OAuthErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
