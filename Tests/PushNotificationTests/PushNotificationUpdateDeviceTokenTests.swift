import Foundation
@testable import PushNotification
import Testing

/// Exercises `updateDeviceToken` through `PushNotificationInterface`. One test per
/// independently-verifiable outcome.
struct PushNotificationUpdateDeviceTokenTests {
    let issuer = "https://issuer.example.com"
    let accountId = "account-1"

    // --- backend accepts ---

    @Test func sendsAnUpdateTokenRequestToTheBackend() async throws {
        let capturedRequest = LockedBox<URLRequest>()
        let sdk = try await enrolledSdk { request in
            capturedRequest.value = request
            return respondSuccess(for: request)
        }

        try await sdk.updateDeviceToken(
            issuer: issuer,
            accountId: accountId,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken
        )

        let request = try #require(capturedRequest.value)
        #expect(request.url?.absoluteString == "\(issuer)/pushNotification/api/v1/updateToken")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/jwt")
    }

    @Test func signsTheAccountIdDeviceTokenTypeAndDeviceTokenAsClaims() async throws {
        let capturedRequest = LockedBox<URLRequest>()
        let sdk = try await enrolledSdk { request in
            capturedRequest.value = request
            return respondSuccess(for: request)
        }

        for deviceTokenType in [DeviceTokenType.apns, .fcmToken, .fcmFid] {
            try await sdk.updateDeviceToken(
                issuer: issuer,
                accountId: accountId,
                deviceToken: "token-for-\(deviceTokenType)",
                deviceTokenType: deviceTokenType
            )

            let claims = try await #require(capturedRequest.value).jwtPayloadClaims()
            #expect(claims["accountId"] == accountId)
            #expect(claims["deviceTokenType"] == deviceTokenType.wireValue)
            #expect(claims["deviceToken"] == "token-for-\(deviceTokenType)")
        }
    }

    // --- backend refuses ---

    @Test func throwsUpdateTokenRejectedCarryingTheStatusCodeWhenTheBackendRefuses() async throws {
        let sdk = try await enrolledSdk { request in respondFailure(for: request) }

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.updateDeviceToken(
                issuer: issuer,
                accountId: accountId,
                deviceToken: "token-abc",
                deviceTokenType: .fcmToken
            )
        }
        #expect(failure.code == "token_update_rejected")
        #expect(failure.status == 400)
    }

    @Test func makesExactlyOneRequestEvenWhenTheBackendFails() async throws {
        let requestCount = LockedBox<Int>()
        requestCount.value = 0
        let sdk = try await enrolledSdk { request in
            requestCount.value = (requestCount.value ?? 0) + 1
            return respondFailure(for: request)
        }

        _ = try? await sdk.updateDeviceToken(
            issuer: issuer,
            accountId: accountId,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken
        )

        #expect(requestCount.value == 1, "the SDK does not retry — retrying is the caller's decision")
    }

    // --- not enrolled ---

    @Test func throwsNotEnrolledWhenNoKeyIsStoredForTheAccount() async throws {
        let sdk = createTestPushNotificationSdk(handleRequest: failIfCalled)

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.updateDeviceToken(
                issuer: issuer,
                accountId: accountId,
                deviceToken: "token-abc",
                deviceTokenType: .fcmToken
            )
        }
        #expect(failure.code == "not_enrolled")
    }

    private func enrolledSdk(handleRequest: @escaping MockURLProtocol.Handler) async throws -> PushNotification {
        let storage = FakePushNotificationStorage()
        _ = try await storage.createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)
        return createTestPushNotificationSdk(storage: storage, handleRequest: handleRequest)
    }
}
