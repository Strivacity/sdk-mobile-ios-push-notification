@testable import PushNotification
import Testing

/// Exercises `Jwk.wireObject` directly — pure logic, no fakes needed. The allowlist restricting
/// which algorithms `enrollDevice` accepts lives elsewhere (`PushNotification.swift`); this wire
/// property itself makes no assumption about the key shape.
struct JwkWireFormatTests {
    @Test func includesEveryMemberPlusAlgAndKid() {
        let jwk = Jwk(
            kid: "key-1",
            alg: "ES256",
            members: ["kty": "EC", "crv": "P-256", "x": "x-coord", "y": "y-coord"]
        )

        let json = jwk.wireObject

        #expect(json["kty"] == "EC")
        #expect(json["crv"] == "P-256")
        #expect(json["x"] == "x-coord")
        #expect(json["y"] == "y-coord")
        #expect(json["alg"] == "ES256")
        #expect(json["kid"] == "key-1")
    }

    @Test func algAndKidWinOverConflictingValuesInMembers() {
        let jwk = Jwk(kid: "real-kid", alg: "ES256", members: ["alg": "spoofed-alg", "kid": "spoofed-kid"])

        let json = jwk.wireObject

        #expect(json["alg"] == "ES256")
        #expect(json["kid"] == "real-kid")
    }

    @Test func serializesAnRsaShapedKeyEvenThoughTodaysAllowlistRejectsIt() {
        let jwk = Jwk(kid: "key-1", alg: "RS256", members: ["kty": "RSA", "n": "modulus", "e": "AQAB"])

        let json = jwk.wireObject

        #expect(json["kty"] == "RSA")
        #expect(json["n"] == "modulus")
        #expect(json["e"] == "AQAB")
    }
}
