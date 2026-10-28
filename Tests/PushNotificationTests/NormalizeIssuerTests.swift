@testable import PushNotification
import Testing

struct NormalizeIssuerTests {
    @Test func lowercasesSchemeAndAuthority() throws {
        #expect(try normalizeIssuer("HTTPS://Issuer.Example.com") == "https://issuer.example.com")
    }

    @Test func spellingsThatMeanTheSameBackendNormaliseAlike() throws {
        let expected = "https://acme.example.com"

        #expect(try normalizeIssuer("https://acme.example.com/") == expected)
        #expect(try normalizeIssuer("  https://acme.example.com  ") == expected)
        #expect(try normalizeIssuer("HTTPS://ACME.Example.com") == expected)
        #expect(try normalizeIssuer("https://acme.example.com/some/path?q=1#x") == expected)
    }

    @Test func keepsAnExplicitPort() throws {
        #expect(try normalizeIssuer("https://issuer.example.com:8443") == "https://issuer.example.com:8443")
    }

    @Test func rejectsANonHttpsScheme() {
        #expect(throws: PushNotificationError.self) {
            try normalizeIssuer("http://issuer.example.com")
        }
    }

    @Test func rejectsAValueThatIsNotAnAbsoluteUrl() {
        #expect(throws: PushNotificationError.self) {
            try normalizeIssuer("acme.example.com")
        }
        #expect(throws: PushNotificationError.self) {
            try normalizeIssuer("")
        }
    }

    @Test func rejectsAMissingHost() {
        #expect(throws: PushNotificationError.self) {
            try normalizeIssuer("https://")
        }
    }

    @Test func rejectsEmbeddedUserInfo() {
        #expect(throws: PushNotificationError.self) {
            try normalizeIssuer("https://user:pass@issuer.example.com")
        }
    }

    @Test func rejectsAnEmbeddedUserWithNoPassword() {
        #expect(throws: PushNotificationError.self) {
            try normalizeIssuer("https://user@issuer.example.com")
        }
    }
}
