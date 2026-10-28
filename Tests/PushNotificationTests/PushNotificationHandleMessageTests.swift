import Foundation
@testable import PushNotification
import Testing

/// Exercises `handleMessage` through `PushNotificationInterface`. One test per
/// independently-verifiable outcome.
struct PushNotificationHandleMessageTests {
    let issuer = "https://issuer.example.com"
    let accountId = "account-1"
    let challengeId = "challenge-1"

    // --- can't even reach the backend ---

    @Test func throwsChallengeUnavailableWhenNoEnvelopeCanBeParsed() async throws {
        let sdk = sdkWithNoStoredKey(handleRequest: failIfCalled)

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.handleMessage(nil)
        }
        #expect(failure.code == "challenge_unavailable")
    }

    @Test func throwsNotEnrolledWhenNoKeyIsStoredForTheAccount() async throws {
        let sdk = sdkWithNoStoredKey(handleRequest: failIfCalled)

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.handleMessage(envelopeMessageData(
                issuer: issuer,
                accountId: accountId,
                challengeId: challengeId
            ))
        }
        #expect(failure.code == "not_enrolled")
    }

    // --- backend accepts ---

    @Test func fetchesTheChallengeFromTheBackend() async throws {
        let capturedRequest = LockedBox<URLRequest>()
        let sdk = try await sdkWithStoredKey { request in
            capturedRequest.value = request
            return respondJson(for: request, body: approveDenyResponseBody())
        }

        _ = try await sdk.handleMessage(envelopeMessageData(
            issuer: issuer,
            accountId: accountId,
            challengeId: challengeId
        ))

        let request = try #require(capturedRequest.value)
        #expect(request.url?.absoluteString == "\(issuer)/pushNotification/api/v1/actions/\(challengeId)")
    }

    @Test func mapsAnApproveDenyResponseToChallengeSimple() async throws {
        let expectedExpiresAt = "2026-10-01T14:30:00Z"
        let sdk = try await sdkWithStoredKey { request in
            respondJson(for: request, body: approveDenyResponseBody(expireAt: expectedExpiresAt))
        }

        let challenge = try await sdk.handleMessage(envelopeMessageData(
            issuer: issuer,
            accountId: accountId,
            challengeId: challengeId
        ))

        guard case .simple = challenge else {
            Issue.record("expected .simple, got \(challenge)")
            return
        }
        #expect(challenge.challengeId == challengeId)
        #expect(challenge.issuer == issuer)
        #expect(challenge.accountId == accountId)
        #expect(challenge.expiresAt == expectedExpiresAt)
    }

    @Test func returnsAnAlreadyPastExpiresAtAsIsWithoutEnforcingIt() async throws {
        let alreadyPastInstant = "1970-01-01T00:00:01Z"
        let sdk = try await sdkWithStoredKey { request in
            respondJson(for: request, body: approveDenyResponseBody(expireAt: alreadyPastInstant))
        }

        let challenge = try await sdk.handleMessage(envelopeMessageData(
            issuer: issuer,
            accountId: accountId,
            challengeId: challengeId
        ))

        #expect(challenge.expiresAt == alreadyPastInstant)
    }

    @Test func mapsAContextMatchingResponseToChallengeContextMatchingWithItsOptions() async throws {
        let sdk = try await sdkWithStoredKey { request in
            respondJson(for: request, body: contextMatchingResponseBody(options: ["12", "26", "84"]))
        }

        let challenge = try await sdk.handleMessage(envelopeMessageData(
            issuer: issuer,
            accountId: accountId,
            challengeId: challengeId
        ))

        guard case let .contextMatching(contextMatching) = challenge else {
            Issue.record("expected .contextMatching, got \(challenge)")
            return
        }
        #expect(contextMatching.options == ["12", "26", "84"])
    }

    @Test func throwsChallengeUnavailableWhenAContextMatchingChallengeArrivesWithNoOptions() async throws {
        // A `select` that could never succeed is a backend contract violation, not a shape the
        // SDK hands the App.
        let sdk = try await sdkWithStoredKey { request in
            respondJson(for: request, body: contextMatchingResponseBody(options: []))
        }

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.handleMessage(envelopeMessageData(
                issuer: issuer,
                accountId: accountId,
                challengeId: challengeId
            ))
        }
        #expect(failure.code == "challenge_unavailable")
    }

    @Test func ignoresUnknownFieldsInTheChallengeResponseBody() async throws {
        let bodyWithUnknownField = """
        {"expireAt":"9999-12-31T23:59:59Z","metadata":{"loginTimestamp":"1700000000"},\
        "action":{"type":"simple"},"aFieldFromANewerBackend":"???"}
        """
        let sdk = try await sdkWithStoredKey { request in respondJson(for: request, body: bodyWithUnknownField) }

        let challenge = try await sdk.handleMessage(envelopeMessageData(
            issuer: issuer,
            accountId: accountId,
            challengeId: challengeId
        ))

        guard case .simple = challenge else {
            Issue.record("expected .simple, got \(challenge)")
            return
        }
    }

    @Test func throwsChallengeUnavailableWhenMetadataIsEmpty() async throws {
        let sdk = try await sdkWithStoredKey { request in
            respondJson(for: request, body: approveDenyResponseBody(metadataJson: "{}"))
        }

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.handleMessage(envelopeMessageData(
                issuer: issuer,
                accountId: accountId,
                challengeId: challengeId
            ))
        }
        #expect(failure.code == "challenge_unavailable")
    }

    @Test func throwsNetworkFailureWhenTheBackendCantBeReached() async throws {
        let sdk = try await sdkWithStoredKey { _ in throw URLError(.notConnectedToInternet) }

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.handleMessage(envelopeMessageData(
                issuer: issuer,
                accountId: accountId,
                challengeId: challengeId
            ))
        }
        #expect(failure.code == "network_failure")
    }

    @Test func passesThroughStringAndNullMetadataValuesAsIs() async throws {
        // The backend contract guarantees every metadata value is a JSON string or null.
        let metadataJson = #"{"place":"New York","flag":null}"#
        let sdk = try await sdkWithStoredKey { request in
            respondJson(for: request, body: approveDenyResponseBody(metadataJson: metadataJson))
        }

        let challenge = try await sdk.handleMessage(envelopeMessageData(
            issuer: issuer,
            accountId: accountId,
            challengeId: challengeId
        ))

        #expect(challenge.metadata == ["place": "New York", "flag": nil])
    }

    @Test func skipsMetadataValuesThatAreNeitherAStringNorNull() async throws {
        let metadataJson = """
        {"place":"New York","count":5,"verified":true,"device":{"os":"iOS"},\
        "tags":["a"],"flag":null,"digits":"5","blank":""}
        """
        let sdk = try await sdkWithStoredKey { request in
            respondJson(for: request, body: approveDenyResponseBody(metadataJson: metadataJson))
        }

        let challenge = try await sdk.handleMessage(envelopeMessageData(
            issuer: issuer,
            accountId: accountId,
            challengeId: challengeId
        ))

        #expect(challenge.metadata == ["place": "New York", "flag": nil, "digits": "5", "blank": ""])
    }

    @Test func returnsEmptyMetadataWhenEveryValueIsOutsideTheContract() async throws {
        let metadataJson = #"{"count":5,"device":{"os":"iOS"}}"#
        let sdk = try await sdkWithStoredKey { request in
            respondJson(for: request, body: approveDenyResponseBody(metadataJson: metadataJson))
        }

        let challenge = try await sdk.handleMessage(envelopeMessageData(
            issuer: issuer,
            accountId: accountId,
            challengeId: challengeId
        ))

        #expect(challenge.metadata.isEmpty)
    }

    @Test func throwsUnsupportedChallengeTypeNamingTheUnrecognizedActionType() async throws {
        let sdk = try await sdkWithStoredKey { request in respondJson(
            for: request,
            body: unsupportedChallengeResponseBody()
        ) }

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.handleMessage(envelopeMessageData(
                issuer: issuer,
                accountId: accountId,
                challengeId: challengeId
            ))
        }
        guard case let .unsupportedChallengeType(challengeType) = failure else {
            Issue.record("expected .unsupportedChallengeType, got \(failure)")
            return
        }
        #expect(challengeType == "aFutureChallengeType")
    }

    // --- backend refuses ---

    @Test func throwsChallengeUnavailableCarryingTheStatusCodeWhenTheBackendRefuses() async throws {
        let sdk = try await sdkWithStoredKey { request in respondFailure(for: request, status: 500) }

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.handleMessage(envelopeMessageData(
                issuer: issuer,
                accountId: accountId,
                challengeId: challengeId
            ))
        }
        #expect(failure.code == "challenge_unavailable")
        #expect(failure.status == 500)
    }

    @Test func throwsChallengeUnavailableWithTheCauseAttachedWhenTheResponseBodyCannotBeParsed() async throws {
        let sdk = try await sdkWithStoredKey { request in respondJson(for: request, body: "not json") }

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.handleMessage(envelopeMessageData(
                issuer: issuer,
                accountId: accountId,
                challengeId: challengeId
            ))
        }
        #expect(failure.cause != nil, "the deserialization failure should be attached as the cause")
    }

    @Test func makesExactlyOneRequestEvenWhenTheBackendFails() async throws {
        let requestCount = LockedBox<Int>()
        requestCount.value = 0
        let sdk = try await sdkWithStoredKey { request in
            requestCount.value = (requestCount.value ?? 0) + 1
            return respondFailure(for: request)
        }

        _ = try? await sdk.handleMessage(envelopeMessageData(
            issuer: issuer,
            accountId: accountId,
            challengeId: challengeId
        ))

        #expect(requestCount.value == 1, "the SDK does not retry — retrying is the caller's decision")
    }

    private func sdkWithStoredKey(handleRequest: @escaping MockURLProtocol.Handler) async throws -> PushNotification {
        let storage = FakePushNotificationStorage()
        _ = try await storage.createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)
        return createTestPushNotificationSdk(storage: storage, handleRequest: handleRequest)
    }

    private func sdkWithNoStoredKey(handleRequest: @escaping MockURLProtocol.Handler) -> PushNotification {
        createTestPushNotificationSdk(handleRequest: handleRequest)
    }
}
