import Foundation

/// Errors that can occur during IdentiMe authentication.
public enum IdentiMeError: Error, LocalizedError, Sendable {
    /// No authorization code was received in the callback URL.
    case noCodeReceived

    /// The user denied the authorization request.
    case authorizationDenied(String)

    /// The IdentiMe configuration is invalid.
    case invalidConfiguration

    /// The server returned an unexpected response.
    case invalidResponse

    /// OAuth error returned by IdentiMe.
    case oauthError(String, String?)

    /// HTTP error from the server.
    case httpError(Int)

    /// Failed to fetch the user profile after authentication.
    case userFetchFailed

    /// A network error occurred.
    case networkError(Error)

    /// One of the configured URLs is malformed.
    case invalidURL

    /// Device-code flow timed out — the user did not approve before
    /// the device_code expired (typically 5-10 minutes).
    case deviceCodeExpired

    public var errorDescription: String? {
        switch self {
        case .noCodeReceived:
            return "No authorization code received from IdentiMe."
        case .authorizationDenied(let reason):
            return "Authorization denied: \(reason)"
        case .invalidConfiguration:
            return "Invalid IdentiMe configuration."
        case .invalidResponse:
            return "Unexpected response from IdentiMe."
        case .oauthError(let error, let description):
            return description ?? error
        case .httpError(let code):
            return "HTTP error \(code) from IdentiMe."
        case .userFetchFailed:
            return "Failed to fetch user profile from IdentiMe."
        case .networkError(let error):
            return error.localizedDescription
        case .invalidURL:
            return "IdentiMe URL is malformed."
        case .deviceCodeExpired:
            return "The sign-in window expired. Please try again."
        }
    }
}
