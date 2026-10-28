@testable import PushNotification
import Testing

/// Exercises `canHandleMessage` through `PushNotificationInterface`. Pure parsing plus a storage
/// lookup — no backend call is ever expected. One test per independently-verifiable outcome.
struct PushNotificationCanHandleMessageTests {
    let issuer = "https://issuer.example.com"
    let accountId = "account-1"

    @Test func returnsFalseWhenThereIsNoMessageData() async throws {
        let sdk = sdkWithNoStoredKey()

        #expect(try await sdk.canHandleMessage(nil) == false)
        #expect(try await sdk.canHandleMessage([:]) == false)
    }

    @Test func returnsFalseWhenTheEnvelopeKeyIsAbsent() async throws {
        let sdk = sdkWithNoStoredKey()

        #expect(try await sdk.canHandleMessage(["some.other.key": "value"]) == false)
    }

    @Test func returnsFalseWhenMessageDataCarriesOnlyUnrelatedKeys() async throws {
        let sdk = sdkWithNoStoredKey()

        let realisticNoise = ["title": "Hello", "body": "You have a notification", "gcm.n.e": "1"]
        #expect(try await sdk.canHandleMessage(realisticNoise) == false)
    }

    @Test func returnsFalseWhenTheEnvelopeValueIsNotValidJson() async throws {
        let sdk = sdkWithNoStoredKey()

        #expect(try await sdk.canHandleMessage([PushEnvelope.key: "not json"]) == false)
    }

    @Test func returnsFalseForAnUnsupportedEnvelopeVersion() async throws {
        let sdk = sdkWithNoStoredKey()

        #expect(try await sdk
            .canHandleMessage(envelopeMessageData(issuer: issuer, accountId: accountId, version: "2")) == false)
    }

    @Test func returnsFalseWhenARequiredEnvelopeFieldIsBlank() async throws {
        let sdk = sdkWithNoStoredKey()

        #expect(try await sdk.canHandleMessage(envelopeMessageData(
            issuer: issuer,
            accountId: accountId,
            challengeId: ""
        )) == false)
        #expect(try await sdk.canHandleMessage(envelopeMessageData(
            issuer: issuer,
            accountId: accountId,
            challenge: ""
        )) == false)
        #expect(try await sdk.canHandleMessage(envelopeMessageData(issuer: issuer, accountId: "")) == false)
        #expect(try await sdk.canHandleMessage(envelopeMessageData(issuer: "", accountId: accountId)) == false)
    }

    @Test func returnsFalseWhenNoKeyIsStoredForTheIssuerAndAccount() async throws {
        let sdk = sdkWithNoStoredKey()

        #expect(try await sdk.canHandleMessage(envelopeMessageData(issuer: issuer, accountId: accountId)) == false)
    }

    @Test func returnsTrueWhenAKeyIsStoredForTheIssuerAndAccount() async throws {
        let sdk = try await sdkWithStoredKey()

        #expect(try await sdk.canHandleMessage(envelopeMessageData(issuer: issuer, accountId: accountId)))
    }

    @Test func returnsFalseForADifferentAccountUnderTheSameIssuer() async throws {
        let sdk = try await sdkWithStoredKey()

        #expect(try await sdk
            .canHandleMessage(envelopeMessageData(issuer: issuer, accountId: "a-different-account")) == false)
    }

    @Test func returnsFalseForADifferentIssuerThanTheOneEnrolled() async throws {
        let sdk = try await sdkWithStoredKey()

        let data = envelopeMessageData(issuer: "https://a-different-issuer.example.com", accountId: accountId)
        #expect(try await sdk.canHandleMessage(data) == false)
    }

    @Test func returnsTrueEvenWhenTheEnvelopeCarriesUnknownExtraFields() async throws {
        let sdk = try await sdkWithStoredKey()
        let envelopeWithExtraField = [
            PushEnvelope.key: """
            {"version":"1","challengeId":"challenge-1","challenge":"challenge-value",\
            "accountId":"\(accountId)","issuer":"\(issuer)","aFieldFromANewerSdk":"???"}
            """,
        ]

        #expect(try await sdk.canHandleMessage(envelopeWithExtraField))
    }

    @Test func returnsFalseForAMalformedIssuerWithoutThrowing() async throws {
        let sdk = sdkWithNoStoredKey()

        #expect(try await sdk.canHandleMessage(envelopeMessageData(issuer: "not a url", accountId: accountId)) == false)
    }

    private func sdkWithStoredKey() async throws -> PushNotification {
        let storage = FakePushNotificationStorage()
        _ = try await storage.createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)
        return createTestPushNotificationSdk(storage: storage, handleRequest: failIfCalled)
    }

    private func sdkWithNoStoredKey() -> PushNotification {
        createTestPushNotificationSdk(handleRequest: failIfCalled)
    }
}
