import Foundation

/// Configuration for IdentiMe OAuth authentication.
///
/// Register your application at your IdentiMe instance to get
/// the client ID and secret.
///
/// ```swift
/// let config = IdentiMeConfig(
///     clientId: "your-client-id",
///     clientSecret: "your-client-secret",
///     identimeURL: "https://identime.example.com",
///     redirectURI: "myapp://callback"
/// )
/// ```
public struct IdentiMeConfig: Sendable {
    public let clientId: String
    public let clientSecret: String
    public let identimeURL: String
    public let redirectURI: String

    /// The OAuth token endpoint derived from the IdentiMe URL.
    public var tokenURL: String { "\(identimeURL)/oauth/token" }

    public init(clientId: String, clientSecret: String, identimeURL: String, redirectURI: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.identimeURL = identimeURL
        self.redirectURI = redirectURI
    }
}
