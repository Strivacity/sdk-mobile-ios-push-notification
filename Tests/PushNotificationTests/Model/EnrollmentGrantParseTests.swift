import Foundation
@testable import PushNotification
import Testing

/// Exercises `EnrollmentGrant.parse`.
struct EnrollmentGrantParseTests {
    @Test func parseReturnsAGrantWithEveryFieldPopulated() throws {
        let grant = try EnrollmentGrant.parse(grantUrl())

        #expect(grant.issuer == "https://issuer.example.com")
        #expect(grant.oneTimeToken == "ott-1")
        #expect(grant.accountId == "account-1")
        #expect(grant.displayUserName == "Jane")
    }

    @Test func parseThrowsNamingTheMissingParameterWhenIssuerIsMissing() throws {
        let failure = try #require(throws: PushNotificationError.self) {
            try EnrollmentGrant.parse(grantUrl(issuer: nil))
        }
        #expect(failure.message.contains("issuer"))
    }

    @Test func parseThrowsNamingTheMissingParameterWhenOneTimeTokenIsMissing() throws {
        let failure = try #require(throws: PushNotificationError.self) {
            try EnrollmentGrant.parse(grantUrl(oneTimeToken: nil))
        }
        #expect(failure.message.contains("one_time_token"))
    }

    @Test func parseThrowsNamingTheMissingParameterWhenAccountIdIsMissing() throws {
        let failure = try #require(throws: PushNotificationError.self) {
            try EnrollmentGrant.parse(grantUrl(accountId: nil))
        }
        #expect(failure.message.contains("account_id"))
    }

    @Test func parseTreatsAPresentButEmptyRequiredParameterAsMissing() throws {
        let failure = try #require(throws: PushNotificationError.self) {
            try EnrollmentGrant.parse(grantUrl(issuer: ""))
        }
        #expect(failure.message.contains("issuer"))
    }

    @Test func parseIgnoresUnknownExtraQueryParameters() throws {
        let url = grantUrl(extraParams: ["utm_source": "email"])

        let grant = try EnrollmentGrant.parse(url)

        #expect(grant.accountId == "account-1")
    }

    @Test func parseThrowsNamingTheMissingParameterWhenUsernameIsMissing() throws {
        let failure1 = try #require(throws: PushNotificationError.self) {
            try EnrollmentGrant.parse(grantUrl(username: nil))
        }
        #expect(failure1.message.contains("username"))

        let failure2 = try #require(throws: PushNotificationError.self) {
            try EnrollmentGrant.parse(grantUrl(username: "   "))
        }
        #expect(failure2.message.contains("username"))
    }

    @Test func parseThrowsInvalidGrantNotACrashForAUrlWithNoQuery() throws {
        // An opaque URL (e.g. "mailto:x", no "//") has no query component to read at all —
        // `URLComponents.queryItems` is simply `nil` for one, so this proves the no-query path
        // throws the typed error cleanly rather than misbehaving in some other way.
        let url = try #require(URL(string: "mailto:someone@example.com"))

        #expect(throws: PushNotificationError.self) {
            try EnrollmentGrant.parse(url)
        }
    }

    @Test func parsePropagatesInvalidIssuerWhenTheIssuerParameterIsNotAValidHttpsUrl() throws {
        let failure = try #require(throws: PushNotificationError.self) {
            try EnrollmentGrant.parse(grantUrl(issuer: "not-a-url"))
        }
        #expect(failure.code == "invalid_issuer")
    }

    @Test func parseUsesTheLastOccurrenceOfARepeatedQueryParameter() throws {
        // Documents current behavior (queryItems.last { ... }) rather than asserting it as an
        // intentional design choice — see the session's collected findings.
        var components = try #require(URLComponents(string: "https://app.example.com/enroll"))
        components.queryItems = [
            URLQueryItem(name: "issuer", value: "https://issuer.example.com"),
            URLQueryItem(name: "one_time_token", value: "first-token"),
            URLQueryItem(name: "one_time_token", value: "second-token"),
            URLQueryItem(name: "account_id", value: "account-1"),
            URLQueryItem(name: "username", value: "Jane"),
        ]

        let grant = try EnrollmentGrant.parse(#require(components.url))

        #expect(grant.oneTimeToken == "second-token")
    }

    private func grantUrl(
        issuer: String? = "https://issuer.example.com",
        oneTimeToken: String? = "ott-1",
        accountId: String? = "account-1",
        username: String? = "Jane",
        extraParams: [String: String] = [:]
    ) -> URL {
        var items: [URLQueryItem] = []
        if let issuer {
            items.append(URLQueryItem(name: "issuer", value: issuer))
        }
        if let oneTimeToken {
            items.append(URLQueryItem(name: "one_time_token", value: oneTimeToken))
        }
        if let accountId {
            items.append(URLQueryItem(name: "account_id", value: accountId))
        }
        if let username {
            items.append(URLQueryItem(name: "username", value: username))
        }
        for (key, value) in extraParams {
            items.append(URLQueryItem(name: key, value: value))
        }

        var components = URLComponents(string: "https://app.example.com/enroll")!
        components.queryItems = items
        return components.url!
    }
}
