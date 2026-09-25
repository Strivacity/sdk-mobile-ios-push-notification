import CryptoKit
@testable import PushNotification
import Testing

/// Exercises `Jwk(p256PublicKey:kid:)` directly — pure CryptoKit logic needing no Keychain/Secure
/// Enclave access, but only ever called from `DefaultPushNotificationStorage` in production.
struct JwkTests {
    let x963Representation = P256.Signing.PrivateKey().publicKey.x963Representation

    @Test func p256PublicKeyCarriesTheGivenKeyIdAndES256AsTheAlgorithm() {
        let jwk = Jwk(p256PublicKey: x963Representation, kid: "key-1")

        #expect(jwk.kid == "key-1")
        #expect(jwk.alg == Jwk.algorithmES256)
    }

    @Test func p256PublicKeysMembersDescribeAnEcP256PublicKeyAndCarryNoKidOrAlg() {
        let jwk = Jwk(p256PublicKey: x963Representation, kid: "key-1")

        #expect(jwk.members["kty"] == "EC")
        #expect(jwk.members["crv"] == "P-256")
        #expect(Set(jwk.members.keys) == ["kty", "crv", "x", "y"])
    }

    @Test func p256PublicKeyNeverIncludesPrivateKeyMaterial() {
        let jwk = Jwk(p256PublicKey: x963Representation, kid: "key-1")

        #expect(Set(jwk.members.keys).isDisjoint(with: Jwk.privateMembers))
    }
}
