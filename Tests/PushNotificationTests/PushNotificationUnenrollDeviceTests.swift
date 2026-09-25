import Foundation
@testable import PushNotification
import Testing

/// Exercises `unenrollDevice` through `PushNotificationInterface`. One test per
/// independently-verifiable outcome.
struct PushNotificationUnenrollDeviceTests {
    let issuer = "https://issuer.example.com"
    let accountId = "account-1"

    // --- backend accepts ---

    @Test func sendsAnUnenrollRequestToTheBackend() async throws {
        let capturedRequest = LockedBox<URLRequest>()
        let storage = try await enrolledStorage()
        let sdk = createTestPushNotificationSdk(storage: storage) { request in
            capturedRequest.value = request
            return respondSuccess(for: request)
        }

        try await sdk.unenrollDevice(issuer: issuer, accountId: accountId)

        let request = try #require(capturedRequest.value)
        #expect(request.url?.absoluteString == "\(issuer)/pushNotification/api/v1/unenroll")
    }

    @Test func signsOnlyTheAccountIdAsAClaimAndIdentifiesTheKeyInTheHeader() async throws {
        let capturedRequest = LockedBox<URLRequest>()
        let storage = try await enrolledStorage()
        let keyId = try #require(await storage.getPublicKey(issuer: issuer, accountId: accountId)).kid
        let sdk = createTestPushNotificationSdk(storage: storage) { request in
            capturedRequest.value = request
            return respondSuccess(for: request)
        }

        try await sdk.unenrollDevice(issuer: issuer, accountId: accountId)

        let request = try #require(capturedRequest.value)
        #expect(try request.jwtPayloadClaims() == ["accountId": accountId])
        #expect(try request.jwtHeaderClaims()["kid"] == keyId)
    }

    @Test func callsTheBackendBeforeRemovingTheLocalKey() async throws {
        let storage = try await enrolledStorage()
        let keyPresentWhenBackendCalled = LockedBox<Bool>()
        let sdk = createTestPushNotificationSdk(storage: storage) { request in
            keyPresentWhenBackendCalled.value = try await storage
                .getPublicKey(issuer: issuer, accountId: accountId) != nil
            return respondSuccess(for: request)
        }

        try await sdk.unenrollDevice(issuer: issuer, accountId: accountId)

        #expect(keyPresentWhenBackendCalled.value == true)
    }

    @Test func removesTheLocalKey() async throws {
        let storage = try await enrolledStorage()
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: respondSuccess)

        try await sdk.unenrollDevice(issuer: issuer, accountId: accountId)

        let key = try await storage.getPublicKey(issuer: issuer, accountId: accountId)
        #expect(key == nil, "the local key should have been removed")
    }

    @Test func removesTheEnrollmentRecord() async throws {
        let storage = try await enrolledStorage()
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: respondSuccess)

        try await sdk.unenrollDevice(issuer: issuer, accountId: accountId)

        #expect(await storage.listEnrollments().isEmpty, "the enrollment record should have been removed")
    }

    // --- backend refuses ---

    @Test func removesTheLocalEnrollmentEvenWhenTheBackendCallFails() async throws {
        let storage = try await enrolledStorage()
        let sdk = createTestPushNotificationSdk(storage: storage) { request in
            respondFailure(for: request)
        }

        _ = try? await sdk.unenrollDevice(issuer: issuer, accountId: accountId)

        let key = try await storage.getPublicKey(issuer: issuer, accountId: accountId)
        #expect(key == nil, "the local key should have been removed regardless of the backend failure")
        #expect(await storage.listEnrollments().isEmpty, "the enrollment record should have been removed too")
    }

    @Test func stillThrowsTheBackendsFailureCarryingTheStatusCodeAfterRemovingTheLocalEnrollment() async throws {
        let storage = try await enrolledStorage()
        let sdk = createTestPushNotificationSdk(storage: storage) { request in
            respondFailure(for: request)
        }

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.unenrollDevice(issuer: issuer, accountId: accountId)
        }
        #expect(failure.code == "unenrollment_rejected")
        #expect(failure.status == 400)
    }

    // --- network failure ---

    @Test func throwsNetworkFailureWhenTheBackendCantBeReached() async throws {
        let storage = try await enrolledStorage()
        let sdk = createTestPushNotificationSdk(storage: storage) { _ in
            throw URLError(.notConnectedToInternet)
        }

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.unenrollDevice(issuer: issuer, accountId: accountId)
        }
        #expect(failure.code == "network_failure")
    }

    @Test func removesTheLocalEnrollmentEvenWhenANetworkFailureOccurs() async throws {
        let storage = try await enrolledStorage()
        let sdk = createTestPushNotificationSdk(storage: storage) { _ in
            throw URLError(.notConnectedToInternet)
        }

        _ = try? await sdk.unenrollDevice(issuer: issuer, accountId: accountId)

        let key = try await storage.getPublicKey(issuer: issuer, accountId: accountId)
        #expect(key == nil, "the local key should have been removed regardless of the network failure")
        #expect(await storage.listEnrollments().isEmpty, "the enrollment record should have been removed too")
    }

    @Test func removesTheLocalEnrollmentEvenWhenCancelledMidBackendCall() async throws {
        let started = Signal()
        let release = Signal()
        let storage = try await enrolledStorage()
        let sdk = createTestPushNotificationSdk(storage: storage) { request in
            await started.fire()
            await release.wait()
            return respondSuccess(for: request)
        }

        let task = Task {
            _ = try? await sdk.unenrollDevice(issuer: issuer, accountId: accountId)
        }
        await started.wait()
        task.cancel()
        await release.fire()
        _ = await task.value

        let key = try await storage.getPublicKey(issuer: issuer, accountId: accountId)
        #expect(key == nil, "the local key should have been removed regardless of the cancellation")
        #expect(await storage.listEnrollments().isEmpty, "the enrollment record should have been removed too")
    }

    // --- not enrolled ---

    @Test func throwsNotEnrolledWhenTheAccountIsNotEnrolled() async throws {
        let sdk = createTestPushNotificationSdk(handleRequest: failIfCalled)

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.unenrollDevice(issuer: issuer, accountId: accountId)
        }
        #expect(failure.code == "not_enrolled")
    }

    // --- removing the local enrollment fails ---

    @Test func throwsTheStorageErrorWhenRemovingTheLocalEnrollmentFails() async throws {
        let storage = try await StorageThrowingOnRemove(delegate: enrolledStorage())
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: respondSuccess)

        await #expect(throws: TestFailure.self) {
            try await sdk.unenrollDevice(issuer: issuer, accountId: accountId)
        }
    }

    @Test func throwsTheStorageErrorRatherThanTheBackendsFailureWhenBothFail() async throws {
        let storage = try await StorageThrowingOnRemove(delegate: enrolledStorage())
        let sdk = createTestPushNotificationSdk(storage: storage) { request in
            respondFailure(for: request)
        }

        await #expect(throws: TestFailure.self) {
            try await sdk.unenrollDevice(issuer: issuer, accountId: accountId)
        }
    }

    @Test func leavesTheEnrollmentInPlaceWhenRemovingTheLocalEnrollmentFails() async throws {
        let fake = try await enrolledStorage()
        let sdk = createTestPushNotificationSdk(
            storage: StorageThrowingOnRemove(delegate: fake),
            handleRequest: respondSuccess
        )

        _ = try? await sdk.unenrollDevice(issuer: issuer, accountId: accountId)

        #expect(await fake.listEnrollments().count == 1, "nothing was removed, so the call can be repeated")
    }

    /// Storage holding an enrollment for `issuer` and `accountId`.
    private func enrolledStorage() async throws -> FakePushNotificationStorage {
        let storage = FakePushNotificationStorage()
        _ = try await storage.createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)
        return storage
    }
}

/// Throws instead of removing the local enrollment.
private struct StorageThrowingOnRemove: PushNotificationStorage {
    let delegate: FakePushNotificationStorage

    func getPublicKey(issuer: String, accountId: String) async throws -> Jwk? {
        try await delegate.getPublicKey(issuer: issuer, accountId: accountId)
    }

    func createSignature(issuer: String, accountId: String, keyId: String, data: String) async throws -> String {
        try await delegate.createSignature(issuer: issuer, accountId: accountId, keyId: keyId, data: data)
    }

    func createEnrollment(issuer: String, accountId: String, userName: String?,
                          deviceName: String?) async throws -> Jwk {
        try await delegate.createEnrollment(
            issuer: issuer,
            accountId: accountId,
            userName: userName,
            deviceName: deviceName
        )
    }

    func listEnrollments() async -> [Enrollment] {
        await delegate.listEnrollments()
    }

    func removeEnrollment(issuer _: String, accountId _: String) async throws {
        throw TestFailure("simulated removal failure")
    }
}
