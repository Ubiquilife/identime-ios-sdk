import Foundation

/// The result of a successful IdentiMe authentication.
public struct IdentiMeToken: Sendable {
    /// The OAuth access token. Use this to authenticate API requests.
    public let accessToken: String

    /// The OAuth refresh token (if provided).
    public let refreshToken: String?

    /// The token type (usually "Bearer").
    public let tokenType: String

    /// Token lifetime in seconds (if provided).
    public let expiresIn: Int?

    /// Space-separated OAuth scope granted by the server. Optional;
    /// only the device-code flow surfaces this today.
    public let scope: String?

    /// The authenticated user's profile from IdentiMe. Optional
    /// because the device-code flow returns a token without forcing
    /// a profile fetch (caller decides whether to GET /api/v0/profile).
    public let user: IdentiMeUser?

    public init(accessToken: String,
                refreshToken: String?,
                tokenType: String,
                expiresIn: TimeInterval?,
                scope: String? = nil,
                user: IdentiMeUser? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn.map { Int($0) }
        self.scope = scope
        self.user = user
    }
}

/// An authenticated user's profile from IdentiMe.
public struct IdentiMeUser: Sendable {
    public let id: String
    public let firstName: String?
    public let lastName: String?
    public let displayName: String?
    public let email: String?
    public let slug: String?
    public let timezone: String?

    /// Full name computed from first + last, falling back to displayName.
    public var fullName: String {
        if let first = firstName, let last = lastName, !first.isEmpty {
            return "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        }
        return displayName ?? ""
    }
}
