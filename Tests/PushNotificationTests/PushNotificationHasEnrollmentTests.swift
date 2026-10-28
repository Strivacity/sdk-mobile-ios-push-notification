@testable import PushNotification
import Testing

/// Exercises `hasEnrollment` through `PushNotificationInterface`. Pure storage lookup against
/// the recorded enrollments — no backend call is ever expected, so every test wires the SDK to
/// fail if one happens.
struct PushNotificationHasEnrollmentTests {
    let issuer = "https://issuer.example.com"
    let accountId = "account-1"

    @Test func returnsTrueWhenAnEnrollmentIsRecordedForTheIssuerAndAccount() async throws {
        let sdk = try await createTestPushNotificationSdk(storage: enrolledStorage(), handleRequest: failIfCalled)

        #expect(try await sdk.hasEnrollment(issuer: issuer, accountId: accountId))
    }

    @Test func returnsFalseWhenNoEnrollmentIsRecorded() async throws {
        let sdk = createTestPushNotificationSdk(handleRequest: failIfCalled)

        #expect(try await sdk.hasEnrollment(issuer: issuer, accountId: accountId) == false)
    }

    @Test func returnsFalseWhenOnlyAKeyWithoutAnEnrollmentRecordIsStored() async throws {
        let storage = FakePushNotificationStorage()
        _ = await storage.storeKeyWithoutEnrollment(issuer: issuer, accountId: accountId)
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: failIfCalled)

        #expect(try await sdk.hasEnrollment(issuer: issuer, accountId: accountId) == false)
    }

    @Test func returnsFalseForADifferentAccountUnderTheSameIssuer() async throws {
        let sdk = try await createTestPushNotificationSdk(storage: enrolledStorage(), handleRequest: failIfCalled)

        #expect(try await sdk.hasEnrollment(issuer: issuer, accountId: "a-different-account") == false)
    }

    @Test func returnsFalseForADifferentIssuerWithTheSameAccount() async throws {
        let sdk = try await createTestPushNotificationSdk(storage: enrolledStorage(), handleRequest: failIfCalled)

        #expect(try await sdk
            .hasEnrollment(issuer: "https://a-different-issuer.example.com", accountId: accountId) == false)
    }

    @Test func findsAnEnrollmentRegardlessOfTheIssuersCasing() async throws {
        let sdk = try await createTestPushNotificationSdk(storage: enrolledStorage(), handleRequest: failIfCalled)

        #expect(try await sdk.hasEnrollment(issuer: "https://ISSUER.EXAMPLE.COM", accountId: accountId))
    }

    @Test func throwsInvalidIssuerForAMalformedIssuer() async throws {
        let sdk = createTestPushNotificationSdk(handleRequest: failIfCalled)

        await #expect(throws: PushNotificationError.self) {
            try await sdk.hasEnrollment(issuer: "not a url", accountId: accountId)
        }
    }

    /// Storage holding an enrollment for `issuer` and `accountId`.
    private func enrolledStorage() async throws -> FakePushNotificationStorage {
        let storage = FakePushNotificationStorage()
        _ = try await storage.createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)
        return storage
    }
}
