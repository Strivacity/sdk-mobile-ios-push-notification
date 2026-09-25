import CryptoKit
import Foundation
@testable import PushNotification
import Testing

/// Exercises `buildSignedJwt` directly — pure logic, a stub `sign` callback, no fakes needed.
struct BuildSignedJwtTests {
    @Test func returnsThreeDotSeparatedSegments() async throws {
        let jwt = try await buildSignedJwt(keyId: "key-1", algorithm: "ES256", payload: #"{"a":"b"}"#) { _ in
            "signature"
        }

        #expect(jwt.split(separator: ".", omittingEmptySubsequences: false).count == 3)
    }

    @Test func theHeaderSegmentDecodesToExactlyAlgKidAndTypJWT() async throws {
        let jwt = try await buildSignedJwt(keyId: "key-1", algorithm: "ES256", payload: #"{"a":"b"}"#) { _ in
            "signature"
        }

        let header = try decodeSegment(jwt, 0)
        #expect(Set(header.keys) == ["alg", "kid", "typ"])
        #expect(header["alg"] == "ES256")
        #expect(header["kid"] == "key-1")
        #expect(header["typ"] == "JWT")
    }

    @Test func theAlgorithmPassedInIsUsedVerbatimNotAConstant() async throws {
        let jwt = try await buildSignedJwt(keyId: "key-1", algorithm: "RS256", payload: #"{"a":"b"}"#) { _ in
            "signature"
        }

        #expect(try decodeSegment(jwt, 0)["alg"] == "RS256")
    }

    @Test func thePayloadSegmentDecodesToExactlyTheJsonStringPassedIn() async throws {
        let jwt = try await buildSignedJwt(
            keyId: "key-1",
            algorithm: "ES256",
            payload: #"{"a":"b","c":1}"#
        ) { _ in "signature" }

        let payloadSegment = String(jwt.split(separator: ".", omittingEmptySubsequences: false)[1])
        let decoded = try #require(Base64Url.decode(payloadSegment))
        #expect(String(data: decoded, encoding: .utf8) == #"{"a":"b","c":1}"#)
    }

    @Test func theSignCallbackReceivesExactlyHeaderDotPayload() async throws {
        let received = LockedBox<String>()

        let jwt = try await buildSignedJwt(keyId: "key-1", algorithm: "ES256", payload: #"{"a":"b"}"#) { signingInput in
            received.value = signingInput
            return "signature"
        }

        let expected = jwt.split(separator: ".", omittingEmptySubsequences: false).dropLast().joined(separator: ".")
        #expect(received.value == expected)
    }

    @Test func theFinalSegmentIsExactlyWhatSignReturnedUnmodified() async throws {
        let jwt = try await buildSignedJwt(keyId: "key-1", algorithm: "ES256", payload: #"{"a":"b"}"#) { _ in
            "not-even-base64url-shaped!!"
        }

        #expect(jwt.split(separator: ".", omittingEmptySubsequences: false).last == "not-even-base64url-shaped!!")
    }

    @Test func aJwtSignedWithARealKeyVerifiesAndCarriesTheHeaderAndPayload() async throws {
        let key = P256.Signing.PrivateKey()
        let payload = #"{"a":"b","c":1}"#

        let jwt = try await buildSignedJwt(keyId: "key-1", algorithm: "ES256", payload: payload) { signingInput in
            try sign(signingInput, with: key)
        }

        #expect(isSignatureValid(jwt, for: key.publicKey))
        let header = try decodeSegment(jwt, 0)
        #expect(header["alg"] == "ES256")
        #expect(header["kid"] == "key-1")
        #expect(header["typ"] == "JWT")
        let payloadSegment = String(jwt.split(separator: ".", omittingEmptySubsequences: false)[1])
        let decoded = try #require(Base64Url.decode(payloadSegment))
        #expect(String(data: decoded, encoding: .utf8) == payload)
    }

    @Test func aJwtWhosePayloadWasChangedAfterSigningDoesNotVerify() async throws {
        let key = P256.Signing.PrivateKey()
        let jwt = try await buildSignedJwt(keyId: "key-1", algorithm: "ES256", payload: #"{"a":"b"}"#) { signingInput in
            try sign(signingInput, with: key)
        }
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        let tampered = "\(segments[0]).\(Base64Url.encode(#"{"a":"evil"}"#)).\(segments[2])"

        #expect(!isSignatureValid(tampered, for: key.publicKey))
    }

    private func sign(_ signingInput: String, with key: P256.Signing.PrivateKey) throws -> String {
        try Base64Url.encode(key.signature(for: Data(signingInput.utf8)).rawRepresentation)
    }

    private func isSignatureValid(_ jwt: String, for publicKey: P256.Signing.PublicKey) -> Bool {
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let signatureData = Base64Url.decode(String(segments[2])),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signatureData) else {
            return false
        }
        return publicKey.isValidSignature(signature, for: Data("\(segments[0]).\(segments[1])".utf8))
    }

    private func decodeSegment(_ jwt: String, _ index: Int) throws -> [String: String] {
        let segment = String(jwt.split(separator: ".", omittingEmptySubsequences: false)[index])
        let data = try #require(Base64Url.decode(segment))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
    }
}
