# IdentiMeAuth SDK

Authenticate users via [IdentiMe](https://identime.ubiqui.life) OAuth from any Apple-platform app — **iOS 16+, macOS 13+**.

Two grant types are supported:

- **`IdentiMeAuth`** — redirect-callback flow. iOS-first; tries to bounce to the IdentiMe app via a custom URL scheme and falls back to Safari. Works on macOS too (always goes to the browser).
- **`IdentiMeDeviceCode`** — OAuth 2.0 Device Authorization Grant (RFC 8628) with PKCE. Multiplatform; no UIKit/AppKit dependency. Designed for desktop / CLI / embedded contexts where a redirect URL is awkward. The user verifies on any browser, the app polls until approved.

## Device-code quick start

```swift
import IdentiMeAuth

let device = IdentiMeDeviceCode(config: IdentiMeConfig(
    clientId: "your-public-client-id",
    clientSecret: "",                       // public client; unused
    identimeURL: "https://identime.example.com",
    redirectURI: "myapp://oauth-callback"    // unused by device flow
))

let token = try await device.signIn(scope: "files:read profile:read") { approval in
    print("Open \(approval.verificationURIComplete) and enter code \(approval.userCode)")
}

// Persist token.accessToken / token.refreshToken in Keychain. Refresh:
let fresh = try await device.refresh(using: token.refreshToken!)
```

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
