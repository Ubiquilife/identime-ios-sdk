import Testing
@testable import IdentiMeAuth

@Test func configBuildsTokenURL() {
    let config = IdentiMeConfig(
        clientId: "test",
        clientSecret: "secret",
        identimeURL: "https://identime.example.com",
        redirectURI: "myapp://callback"
    )
    #expect(config.tokenURL == "https://identime.example.com/oauth/token")
}

@Test func userFullNameFromParts() {
    let user = IdentiMeUser(
        id: "1",
        firstName: "Emma",
        lastName: "Mitchell",
        displayName: nil,
        email: nil,
        slug: nil,
        timezone: nil
    )
    #expect(user.fullName == "Emma Mitchell")
}

@Test func userFullNameFallsBackToDisplayName() {
    let user = IdentiMeUser(
        id: "1",
        firstName: nil,
        lastName: nil,
        displayName: "Emma Mitchell",
        email: nil,
        slug: nil,
        timezone: nil
    )
    #expect(user.fullName == "Emma Mitchell")
}
