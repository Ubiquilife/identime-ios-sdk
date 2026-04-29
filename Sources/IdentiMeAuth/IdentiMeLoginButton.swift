import SwiftUI

/// A pre-built SwiftUI login button for IdentiMe authentication.
///
/// ```swift
/// struct LoginScreen: View {
///     let auth = IdentiMeAuth(config: myConfig)
///     @State private var error: String?
///
///     var body: some View {
///         IdentiMeLoginButton(auth: auth) { result in
///             switch result {
///             case .success(let token):
///                 // Store token, navigate to main app
///             case .failure(let error):
///                 self.error = error.localizedDescription
///             }
///         }
///     }
/// }
/// ```
public struct IdentiMeLoginButton: View {
    private let auth: IdentiMeAuth
    private let onResult: (Result<IdentiMeToken, IdentiMeError>) -> Void
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(auth: IdentiMeAuth, onResult: @escaping (Result<IdentiMeToken, IdentiMeError>) -> Void) {
        self.auth = auth
        self.onResult = onResult
    }

    public var body: some View {
        VStack(spacing: 12) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                isLoading = true
                errorMessage = nil
                auth.login()
            } label: {
                if isLoading {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.key")
                        Text("Login with IdentiMe")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
            .background(.white)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(isLoading)
        }
        .onOpenURL { url in
            auth.handleCallback(url: url) { result in
                isLoading = false
                switch result {
                case .failure(let error):
                    errorMessage = error.localizedDescription
                default:
                    break
                }
                onResult(result)
            }
        }
    }
}
