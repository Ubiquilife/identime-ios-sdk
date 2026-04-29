# IdentiMeAuth iOS SDK

Authenticate iOS app users via [IdentiMe](https://identime.test) OAuth.

## Installation

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/Ubiquilife/identime-ios-sdk.git", from: "1.0.0"),
```

Then add `IdentiMeAuth` as a dependency to your target.

## Quick Start

```swift
import SwiftUI
import IdentiMeAuth

@main
struct MyApp: App {
    let auth = IdentiMeAuth(config: IdentiMeConfig(
        clientId: "your-client-id",
        clientSecret: "your-client-secret",
        identimeURL: "https://identime.example.com",
        redirectURI: "myapp://callback"
    ))

    @State private var token: IdentiMeToken?

    var body: some Scene {
        WindowGroup {
            if let token {
                ContentView(token: token)
            } else {
                IdentiMeLoginButton(auth: auth) { result in
                    if case .success(let t) = result {
                        token = t
                    }
                }
                .padding(32)
            }
        }
    }
}
```

## What You Get

After successful authentication, `IdentiMeToken` contains:

- `accessToken` - OAuth access token for API requests
- `refreshToken` - OAuth refresh token (if provided)
- `user.id` - IdentiMe user ID
- `user.fullName` - User's display name
- `user.email` - User's email address

## URL Scheme

Register a URL scheme in your Info.plist (e.g. `myapp`) and set
`redirectURI` to `myapp://callback`. IdentiMe will redirect back
to your app after authentication.

## Requirements

- iOS 16+
- An IdentiMe OAuth application (register at your IdentiMe instance)
