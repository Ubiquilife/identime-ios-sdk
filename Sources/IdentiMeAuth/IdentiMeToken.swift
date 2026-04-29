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

    /// The authenticated user's profile from IdentiMe.
    public let user: IdentiMeUser
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
