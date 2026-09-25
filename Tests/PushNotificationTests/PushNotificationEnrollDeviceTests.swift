import Foundation
@testable import PushNotification
import Testing

/// Exercises `enrollDevice` through `PushNotificationInterface`.
///
/// One test per independently-verifiable outcome, not one test asserting all of them.
struct PushNotificationEnrollDeviceTests {
    let grant = EnrollmentGrant(
        issuer: "https://issuer.example.com",
        oneTimeToken: "ott-1",
        accountId: "account-1",
        displayUserName: "Jane"
    )

    // --- backend accepts ---

    @Test func generatesAKeyForTheAccount() async throws {
        let storage = FakePushNotificationStorage()
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: respondSuccess)

        _ = try await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        let key = try await storage.getPublicKey(issuer: grant.issuer, accountId: grant.accountId)
        #expect(key != nil, "a key should have been generated for this issuer and account")
    }

    @Test func normalizesANonCanonicalIssuerSoLaterCallsCanStillFindTheKey() async throws {
        // EnrollmentGrant's initializer is public and unvalidated — only .parse(URL) normalizes,
        // so a grant built directly (as here) can carry a non-canonical issuer.
        let nonCanonicalGrant = EnrollmentGrant(
            issuer: "https://Issuer.Example.COM",
            oneTimeToken: grant.oneTimeToken,
            accountId: grant.accountId,
            displayUserName: grant.displayUserName
        )
        let storage = FakePushNotificationStorage()
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: respondSuccess)

        _ = try await sdk.enrollDevice(
            grant: nonCanonicalGrant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        let key = try await storage.getPublicKey(
            issuer: "https://issuer.example.com",
            accountId: nonCanonicalGrant.accountId
        )
        #expect(
            key != nil,
            "the key should be stored under the normalized issuer, findable the same way every other method looks it up"
        )
    }

    @Test func sendsAnEnrollRequestToTheBackend() async throws {
        let capturedRequest = LockedBox<URLRequest>()
        let sdk = createTestPushNotificationSdk { request in
            capturedRequest.value = request
            return respondSuccess(for: request)
        }

        _ = try await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        let request = try #require(capturedRequest.value)
        #expect(request.url?.absoluteString == "\(grant.issuer)/pushNotification/api/v1/enroll")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(grant.oneTimeToken)")
    }

    @Test func sendsThePlatformAndPublicKeyInTheRequestBody() async throws {
        let capturedRequest = LockedBox<URLRequest>()
        let storage = FakePushNotificationStorage()
        let sdk = createTestPushNotificationSdk(storage: storage) { request in
            capturedRequest.value = request
            return respondSuccess(for: request)
        }

        _ = try await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        let request = try #require(capturedRequest.value)
        let bodyData = try request.bodyData()
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let publicKey = try #require(body["publicKey"] as? [String: String])
        let storedKey = try #require(await storage.getPublicKey(issuer: grant.issuer, accountId: grant.accountId))
        #expect(body["platform"] as? String == "ios")
        #expect(publicKey["kid"] == storedKey.kid)
        #expect(publicKey["alg"] == storedKey.alg)
        for (name, value) in storedKey.members {
            #expect(publicKey[name] == value)
        }
    }

    @Test func allowsTheSameAccountUnderADifferentIssuer() async throws {
        let storage = FakePushNotificationStorage()
        try await seedEnrollment(in: storage)
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: respondSuccess)
        let differentIssuerGrant = EnrollmentGrant(
            issuer: "https://a-different-issuer.example.com",
            oneTimeToken: grant.oneTimeToken,
            accountId: grant.accountId,
            displayUserName: grant.displayUserName
        )

        _ = try await sdk.enrollDevice(
            grant: differentIssuerGrant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        let key = try await storage.getPublicKey(
            issuer: differentIssuerGrant.issuer,
            accountId: differentIssuerGrant.accountId
        )
        #expect(key != nil)
    }

    @Test func allowsADifferentAccountUnderTheSameIssuer() async throws {
        let storage = FakePushNotificationStorage()
        try await seedEnrollment(in: storage)
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: respondSuccess)
        let differentAccountGrant = EnrollmentGrant(
            issuer: grant.issuer,
            oneTimeToken: grant.oneTimeToken,
            accountId: "a-different-account",
            displayUserName: grant.displayUserName
        )

        _ = try await sdk.enrollDevice(
            grant: differentAccountGrant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        let key = try await storage.getPublicKey(
            issuer: differentAccountGrant.issuer,
            accountId: differentAccountGrant.accountId
        )
        #expect(key != nil)
    }

    @Test func recordsTheNewEnrollment() async throws {
        let storage = FakePushNotificationStorage()
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: respondSuccess)

        let enrollment = try await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "My Phone"
        )

        let keyId = try #require(await storage.getPublicKey(issuer: grant.issuer, accountId: grant.accountId)).kid
        let expected = Enrollment(
            issuer: grant.issuer,
            accountId: grant.accountId,
            keyId: keyId,
            userName: "Jane",
            deviceName: "My Phone"
        )
        #expect(enrollment == expected)
        #expect(await storage.listEnrollments() == [enrollment])
    }

    @Test func recordsTheEnrollmentBeforeCallingTheBackend() async throws {
        let storage = FakePushNotificationStorage()
        let enrollmentsWhenBackendCalled = LockedBox<[Enrollment]>()
        let sdk = createTestPushNotificationSdk(storage: storage) { request in
            enrollmentsWhenBackendCalled.value = await storage.listEnrollments()
            return respondSuccess(for: request)
        }

        let enrollment = try await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        #expect(enrollmentsWhenBackendCalled.value == [enrollment])
    }

    // --- backend refuses ---

    @Test func throwsEnrollmentRejectedCarryingTheStatusCodeWhenTheBackendRefuses() async throws {
        let sdk = createTestPushNotificationSdk { request in
            respondFailure(for: request, status: 400)
        }

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.enrollDevice(
                grant: grant,
                deviceToken: "token-abc",
                deviceTokenType: .fcmToken,
                deviceName: "device"
            )
        }

        #expect(failure.code == "enrollment_rejected")
        #expect(failure.status == 400)
    }

    @Test func succeedsOnALaterAttemptAfterAnEarlierBackendRefusalRolledBackTheEnrollment() async throws {
        let storage = FakePushNotificationStorage()
        let shouldFail = LockedBox<Bool>()
        shouldFail.value = true
        let sdk = createTestPushNotificationSdk(storage: storage) { request in
            (shouldFail.value ?? false) ? respondFailure(for: request) : respondSuccess(for: request)
        }

        _ = try? await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )
        shouldFail.value = false
        _ = try await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        let key = try await storage.getPublicKey(issuer: grant.issuer, accountId: grant.accountId)
        #expect(key != nil)
    }

    @Test func removesTheGeneratedKeyWhenTheBackendRefuses() async throws {
        let storage = FakePushNotificationStorage()
        let sdk = createTestPushNotificationSdk(storage: storage) { request in
            respondFailure(for: request)
        }

        _ = try? await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        let key = try await storage.getPublicKey(issuer: grant.issuer, accountId: grant.accountId)
        #expect(key == nil, "the generated key should have been rolled back")
    }

    @Test func removesTheRecordedEnrollmentWhenTheBackendRefuses() async {
        let storage = FakePushNotificationStorage()
        let sdk = createTestPushNotificationSdk(storage: storage) { request in
            respondFailure(for: request)
        }

        _ = try? await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        #expect(await storage.listEnrollments().isEmpty, "the recorded enrollment should have been rolled back")
    }

    // --- network failure ---

    @Test func throwsNetworkFailureWhenTheBackendCantBeReached() async throws {
        let sdk = createTestPushNotificationSdk { _ in
            throw URLError(.notConnectedToInternet)
        }

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.enrollDevice(
                grant: grant,
                deviceToken: "token-abc",
                deviceTokenType: .fcmToken,
                deviceName: "device"
            )
        }
        #expect(failure.code == "network_failure")
    }

    @Test func rollsBackTheEnrollmentWhenANetworkFailureOccurs() async throws {
        let storage = FakePushNotificationStorage()
        let sdk = createTestPushNotificationSdk(storage: storage) { _ in
            throw URLError(.notConnectedToInternet)
        }

        _ = try? await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        let key = try await storage.getPublicKey(issuer: grant.issuer, accountId: grant.accountId)
        #expect(key == nil, "the generated key should have been rolled back")
        #expect(await storage.listEnrollments().isEmpty, "the recorded enrollment should have been rolled back")
    }

    @Test func rollsBackTheEnrollmentWhenCancelledMidNetworkCall() async throws {
        let started = Signal()
        let release = Signal()
        let storage = FakePushNotificationStorage()
        let sdk = createTestPushNotificationSdk(storage: storage) { request in
            await started.fire()
            await release.wait()
            return respondSuccess(for: request)
        }

        let task = Task {
            _ = try? await sdk.enrollDevice(
                grant: grant,
                deviceToken: "token-abc",
                deviceTokenType: .fcmToken,
                deviceName: "device"
            )
        }
        await started.wait()
        task.cancel()
        await release.fire()
        _ = await task.value

        let key = try await storage.getPublicKey(issuer: grant.issuer, accountId: grant.accountId)
        #expect(key == nil, "the generated key should have been rolled back, not leaked, when cancelled")
        #expect(await storage.listEnrollments().isEmpty, "the recorded enrollment should have been rolled back")
    }

    // --- already enrolled ---

    @Test func throwsAlreadyEnrolledWhenAnEnrollmentIsRecordedForTheAccount() async throws {
        let storage = FakePushNotificationStorage()
        try await seedEnrollment(in: storage)
        // Wired to fail the test if a network call happens — proves "no network call is made" is
        // true, not just unasserted.
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: failIfCalled)

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.enrollDevice(
                grant: grant,
                deviceToken: "token-abc",
                deviceTokenType: .fcmToken,
                deviceName: "device"
            )
        }
        #expect(failure.code == "already_enrolled")
    }

    @Test func doesNotReplaceTheExistingKeyWhenAlreadyEnrolled() async throws {
        let storage = FakePushNotificationStorage()
        let existingKeyId = try await seedEnrollment(in: storage)
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: failIfCalled)

        _ = try? await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        let key = try await storage.getPublicKey(issuer: grant.issuer, accountId: grant.accountId)
        #expect(key?.kid == existingKeyId)
    }

    @Test func throwsAlreadyEnrolledWhenCreatingTheEnrollmentLosesARaceAgainstAConcurrentCall() async throws {
        let storage = StorageReplacingCreateEnrollment(delegate: FakePushNotificationStorage()) { issuer, accountId in
            throw PushNotificationError.alreadyEnrolled(issuer: issuer, accountId: accountId)
        }
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: failIfCalled)

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.enrollDevice(
                grant: grant,
                deviceToken: "token-abc",
                deviceTokenType: .fcmToken,
                deviceName: "device"
            )
        }

        guard case let .alreadyEnrolled(issuer, accountId) = failure else {
            Issue.record("expected .alreadyEnrolled, got \(failure)")
            return
        }
        #expect(issuer == grant.issuer)
        #expect(accountId == grant.accountId)
    }

    // --- a key left behind with no enrollment record ---

    @Test func replacesAKeyStoredWithoutAnEnrollmentRecord() async throws {
        let storage = FakePushNotificationStorage()
        let leftoverKeyId = await storage.storeKeyWithoutEnrollment(issuer: grant.issuer, accountId: grant.accountId)
            .kid
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: respondSuccess)

        let enrollment = try await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        #expect(enrollment.keyId != leftoverKeyId)
        await #expect(throws: TestFailure.self, "the leftover key should be gone, not just shadowed") {
            try await storage.createSignature(
                issuer: grant.issuer,
                accountId: grant.accountId,
                keyId: leftoverKeyId,
                data: "data"
            )
        }
    }

    @Test func recordsTheEnrollmentWhenReplacingAKeyStoredWithoutAnEnrollmentRecord() async throws {
        let storage = FakePushNotificationStorage()
        _ = await storage.storeKeyWithoutEnrollment(issuer: grant.issuer, accountId: grant.accountId)
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: respondSuccess)

        let enrollment = try await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        #expect(await storage.listEnrollments() == [enrollment])
    }

    // --- order of storage operations ---

    @Test func clearsWhateverIsStoredForTheAccountBeforeCreatingTheEnrollment() async throws {
        let log = CallLog()
        let storage = RecordingStorage(delegate: FakePushNotificationStorage(), log: log)
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: respondSuccess)

        _ = try await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        #expect(await log.entries == ["removeEnrollment", "createEnrollment"])
    }

    // --- creating the enrollment fails ---

    @Test func throwsTheStorageFailureWithoutCallingTheBackendWhenCreatingTheEnrollmentFails() async throws {
        let storage = StorageReplacingCreateEnrollment(delegate: FakePushNotificationStorage()) { _, _ in
            throw PushNotificationError.storageFailure(message: "simulated failure", cause: nil)
        }
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: failIfCalled)

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.enrollDevice(
                grant: grant,
                deviceToken: "token-abc",
                deviceTokenType: .fcmToken,
                deviceName: "device"
            )
        }
        #expect(failure.code == "storage_failure")
    }

    // --- storage returns a key the SDK can't accept ---

    @Test func throwsStorageFailureWhenStorageReturnsPrivateKeyMaterial() async throws {
        let sdk = createTestPushNotificationSdk(
            storage: storageReturningPrivateKeyMaterial(FakePushNotificationStorage()),
            handleRequest: failIfCalled
        )

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.enrollDevice(
                grant: grant,
                deviceToken: "token-abc",
                deviceTokenType: .fcmToken,
                deviceName: "device"
            )
        }
        #expect(failure.code == "storage_failure")
    }

    @Test func rollsBackTheEnrollmentWhenItsKeyCarriesPrivateKeyMaterial() async throws {
        let fake = FakePushNotificationStorage()
        let sdk = createTestPushNotificationSdk(
            storage: storageReturningPrivateKeyMaterial(fake),
            handleRequest: failIfCalled
        )

        _ = try? await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        let key = try await fake.getPublicKey(issuer: grant.issuer, accountId: grant.accountId)
        #expect(key == nil)
        #expect(await fake.listEnrollments().isEmpty)
    }

    @Test func throwsUnsupportedAlgorithmWhenStorageReturnsAnUnacceptedAlgorithm() async throws {
        let sdk = createTestPushNotificationSdk(
            storage: storageReturningUnsupportedAlgorithm(FakePushNotificationStorage()),
            handleRequest: failIfCalled
        )

        let failure = try await #require(throws: PushNotificationError.self) {
            try await sdk.enrollDevice(
                grant: grant,
                deviceToken: "token-abc",
                deviceTokenType: .fcmToken,
                deviceName: "device"
            )
        }
        #expect(failure.code == "unsupported_algorithm")
    }

    @Test func rollsBackTheEnrollmentWhenItsKeysAlgorithmIsNotAccepted() async throws {
        let fake = FakePushNotificationStorage()
        let sdk = createTestPushNotificationSdk(
            storage: storageReturningUnsupportedAlgorithm(fake),
            handleRequest: failIfCalled
        )

        _ = try? await sdk.enrollDevice(
            grant: grant,
            deviceToken: "token-abc",
            deviceTokenType: .fcmToken,
            deviceName: "device"
        )

        let key = try await fake.getPublicKey(issuer: grant.issuer, accountId: grant.accountId)
        #expect(key == nil)
        #expect(await fake.listEnrollments().isEmpty)
    }

    /// Records an enrollment for `grant`'s issuer and account. Returns its key's id.
    @discardableResult
    private func seedEnrollment(in storage: FakePushNotificationStorage) async throws -> String {
        try await storage.createEnrollment(
            issuer: grant.issuer,
            accountId: grant.accountId,
            userName: nil,
            deviceName: nil
        ).kid
    }

    /// Creates enrollments through `fake`, but returns their key with a private member added.
    private func storageReturningPrivateKeyMaterial(
        _ fake: FakePushNotificationStorage
    ) -> StorageReplacingCreateEnrollment {
        StorageReplacingCreateEnrollment(delegate: fake) { issuer, accountId in
            let key = try await fake.createEnrollment(
                issuer: issuer,
                accountId: accountId,
                userName: nil,
                deviceName: nil
            )
            var members = key.members
            members[Jwk.privateMembers.sorted()[0]] = "leaked-private-value"
            return Jwk(kid: key.kid, alg: key.alg, members: members)
        }
    }

    /// Creates enrollments through `fake`, but returns their key under an algorithm the SDK does
    /// not accept.
    private func storageReturningUnsupportedAlgorithm(
        _ fake: FakePushNotificationStorage
    ) -> StorageReplacingCreateEnrollment {
        StorageReplacingCreateEnrollment(delegate: fake) { issuer, accountId in
            let key = try await fake.createEnrollment(
                issuer: issuer,
                accountId: accountId,
                userName: nil,
                deviceName: nil
            )
            return Jwk(kid: key.kid, alg: "RS256", members: key.members)
        }
    }
}

/// Delegates to a fake, except for `createEnrollment`, which `replacement` handles instead.
private struct StorageReplacingCreateEnrollment: PushNotificationStorage {
    let delegate: FakePushNotificationStorage
    let replacement: @Sendable (_ issuer: String, _ accountId: String) async throws -> Jwk

    func getPublicKey(issuer: String, accountId: String) async throws -> Jwk? {
        try await delegate.getPublicKey(issuer: issuer, accountId: accountId)
    }

    func createSignature(issuer: String, accountId: String, keyId: String, data: String) async throws -> String {
        try await delegate.createSignature(issuer: issuer, accountId: accountId, keyId: keyId, data: data)
    }

    func createEnrollment(issuer: String, accountId: String, userName _: String?,
                          deviceName _: String?) async throws -> Jwk {
        try await replacement(issuer, accountId)
    }

    func listEnrollments() async -> [Enrollment] {
        await delegate.listEnrollments()
    }

    func removeEnrollment(issuer: String, accountId: String) async throws {
        try await delegate.removeEnrollment(issuer: issuer, accountId: accountId)
    }
}
