import Foundation
@testable import PushNotification
import Testing

/// Exercises `resolveChallenge` through `PushNotificationInterface`. One test per
/// independently-verifiable outcome.
///
/// A `ChallengeResolution` is built directly here (its initializer is internal, visible from this
/// module via `@testable import`) rather than via `Challenge.deny()`/`approve()`/`select()` —
/// those build the right `action` string, which is a separate concern from what `resolveChallenge`
/// itself does with a resolution it's handed.
struct PushNotificationResolveChallengeTests {
    let issuer = "https://issuer.example.com"
    let accountId = "account-1"
    let challengeId = "challenge-1"
    let challengeValue = "challenge-value"

    // --- not enrolled ---

    @Test func throwsNotEnrolledWhenNoKeyIsStoredForTheAccount() async throws {
        let sdk = createTestPushNotificationSdk(handleRequest: failIfCalled)

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.resolveChallenge(resolution(action: "approve"))
        }
        #expect(failure.code == "not_enrolled")
    }

    // --- backend accepts ---

    @Test func sendsAResolutionRequestToTheBackend() async throws {
        let capturedRequest = LockedBox<URLRequest>()
        let sdk = try await enrolledSdk { request in
            capturedRequest.value = request
            return respondSuccess(for: request)
        }

        _ = try await sdk.resolveChallenge(resolution(action: "approve"))

        let request = try #require(capturedRequest.value)
        #expect(request.url?.absoluteString == "\(issuer)/pushNotification/api/v1/actions/\(challengeId)/submit")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/jwt")
        let segments = try request.jwtBody().split(separator: ".", omittingEmptySubsequences: false)
        #expect(segments.count == 3, "the request body should be nothing but the JWT")
    }

    @Test func signsTheChallengeIdChallengeValueAndActionAsClaims() async throws {
        let capturedRequest = LockedBox<URLRequest>()
        let storage = FakePushNotificationStorage()
        let storedKey = try await storage.createEnrollment(
            issuer: issuer,
            accountId: accountId,
            userName: nil,
            deviceName: nil
        )
        let sdk = createTestPushNotificationSdk(storage: storage) { request in
            capturedRequest.value = request
            return respondSuccess(for: request)
        }

        _ = try await sdk.resolveChallenge(resolution(action: "approve"))

        let request = try #require(capturedRequest.value)
        let payload = try request.jwtPayloadClaims()
        #expect(payload["challengeId"] == challengeId)
        #expect(payload["challenge"] == challengeValue)
        #expect(payload["action"] == "approve")
        #expect(try request.jwtHeaderClaims()["kid"] == storedKey.kid)
    }

    @Test func usesTheResolutionsIssuerAsIsWithoutNormalizingIt() async throws {
        let storage = FakePushNotificationStorage()
        // Stored under a normalized issuer, as a real enrollment always would be.
        _ = try await storage.createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: failIfCalled)

        // A differently-cased issuer would normalize to the same value elsewhere in the SDK (e.g.
        // hasEnrollment), but resolveChallenge trusts the resolution's issuer as given — a
        // ChallengeResolution only ever comes from the SDK's own Challenge, whose issuer was
        // already normalized when it was built.
        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.resolveChallenge(resolution(issuer: "https://ISSUER.EXAMPLE.COM", action: "approve"))
        }
        #expect(failure.code == "not_enrolled")
    }

    @Test func returnsOkWhenTheBackendAcceptsADenial() async throws {
        let sdk = try await enrolledSdk(handleRequest: respondSuccess)

        let result = try await sdk.resolveChallenge(resolution(action: "deny"))

        #expect(result == .ok)
    }

    @Test func returnsNotOkWhenTheBackendRecordsARefusal() async throws {
        for rejectionStatus in [400, 401, 404] {
            let sdk = try await enrolledSdk { request in respondFailure(for: request, status: rejectionStatus) }

            let result = try await sdk.resolveChallenge(resolution(action: "approve"))

            #expect(result == .notOk, "status \(rejectionStatus) should map to .notOk")
        }
    }

    // --- backend fails unexpectedly ---

    @Test func throwsChallengeUnavailableWhenTheBackendFailsUnexpectedly() async throws {
        let sdk = try await enrolledSdk { request in respondFailure(for: request, status: 500) }

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.resolveChallenge(resolution(action: "approve"))
        }
        #expect(failure.code == "challenge_unavailable")
    }

    @Test func makesExactlyOneRequestEvenWhenTheBackendFails() async throws {
        let requestCount = LockedBox<Int>()
        requestCount.value = 0
        let sdk = try await enrolledSdk { request in
            requestCount.value = (requestCount.value ?? 0) + 1
            return respondFailure(for: request, status: 500)
        }

        _ = try? await sdk.resolveChallenge(resolution(action: "approve"))

        #expect(requestCount.value == 1, "the SDK does not retry — retrying is the caller's decision")
    }

    private func resolution(issuer: String? = nil, action: String) -> ChallengeResolution {
        ChallengeResolution(
            challengeId: challengeId,
            challengeValue: challengeValue,
            issuer: issuer ?? self.issuer,
            accountId: accountId,
            action: action
        )
    }

    private func enrolledSdk(handleRequest: @escaping MockURLProtocol.Handler) async throws -> PushNotification {
        let storage = FakePushNotificationStorage()
        _ = try await storage.createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)
        return createTestPushNotificationSdk(storage: storage, handleRequest: handleRequest)
    }
}
