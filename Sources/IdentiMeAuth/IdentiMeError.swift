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
        }
    }
}
