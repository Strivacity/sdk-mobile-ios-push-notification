@testable import PushNotification
import Testing

/// Exercises `KeyAlias` directly — pure logic, otherwise exercised only indirectly through
/// `DefaultPushNotificationStorage`. None of this needs a device or Secure Enclave access.
struct KeyAliasTests {
    @Test func prefixForIsStableAcrossCallsForTheSameIssuerAndAccount() {
        let first = KeyAlias.prefixFor(issuer: "https://issuer.example.com", accountId: "account-1")
        let second = KeyAlias.prefixFor(issuer: "https://issuer.example.com", accountId: "account-1")

        #expect(first == second)
    }

    @Test func prefixForChangesWhenTheIssuerOrTheAccountChanges() {
        let base = KeyAlias.prefixFor(issuer: "https://issuer.example.com", accountId: "account-1")

        #expect(base != KeyAlias.prefixFor(issuer: "https://a-different-issuer.example.com", accountId: "account-1"))
        #expect(base != KeyAlias.prefixFor(issuer: "https://issuer.example.com", accountId: "a-different-account"))
    }

    @Test func prefixForDistinguishesIssuerAndAccountRatherThanJustConcatenatingThem() {
        // Without a delimiter between the two, ("ab", "c") and ("a", "bc") would hash identically.
        let first = KeyAlias.prefixFor(issuer: "ab", accountId: "c")
        let second = KeyAlias.prefixFor(issuer: "a", accountId: "bc")

        #expect(first != second)
    }

    @Test func newKeyIdNeverContainsTheSeparatorCharacter() throws {
        for _ in 0 ..< 1000 {
            #expect(try !KeyAlias.newKeyId().contains("."))
        }
    }

    @Test func keyIdOfRoundTripsTheKeyId() {
        let alias = KeyAlias.of(issuer: "https://issuer.example.com", accountId: "account-1", keyId: "key-1")

        #expect(KeyAlias.keyIdOf(alias) == "key-1")
    }

    @Test func isOursAcceptsAnAliasBuiltByOf() {
        let alias = KeyAlias.of(issuer: "https://issuer.example.com", accountId: "account-1", keyId: "key-1")

        #expect(KeyAlias.isOurs(alias))
    }

    @Test func isOursRejectsAnAliasBelongingToTheHostApp() {
        #expect(!KeyAlias.isOurs("some_app_owned_alias"))
    }
}
