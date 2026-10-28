@testable import PushNotification
import Testing

/// Exercises `listEnrollments` through `PushNotificationInterface`. Pure pass-through to
/// `PushNotificationStorage.listEnrollments` — no backend call is ever expected.
struct PushNotificationListEnrollmentsTests {
    @Test func returnsAnEmptyListWhenNothingIsEnrolled() async {
        let sdk = createTestPushNotificationSdk(handleRequest: failIfCalled)

        #expect(await sdk.listEnrollments().isEmpty)
    }

    @Test func returnsExactlyWhatStorageHasRecorded() async throws {
        // Compared without relying on order: Swift's `Dictionary` makes no ordering guarantee,
        // and neither does the Keychain the shipped storage reads from.
        let storage = FakePushNotificationStorage()
        let firstKey = try await storage.createEnrollment(
            issuer: "https://issuer-a.example.com",
            accountId: "account-1",
            userName: "Jane",
            deviceName: "Pixel"
        )
        let secondKey = try await storage.createEnrollment(
            issuer: "https://issuer-b.example.com",
            accountId: "account-2",
            userName: nil,
            deviceName: nil
        )
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: failIfCalled)

        let result = await sdk.listEnrollments()
        #expect(result.count == 2)
        #expect(result.contains(Enrollment(
            issuer: "https://issuer-a.example.com",
            accountId: "account-1",
            keyId: firstKey.kid,
            userName: "Jane",
            deviceName: "Pixel"
        )))
        #expect(result.contains(Enrollment(
            issuer: "https://issuer-b.example.com",
            accountId: "account-2",
            keyId: secondKey.kid,
            userName: nil,
            deviceName: nil
        )))
    }

    @Test func omitsAKeyStoredWithoutAnEnrollmentRecord() async {
        let storage = FakePushNotificationStorage()
        _ = await storage.storeKeyWithoutEnrollment(issuer: "https://issuer.example.com", accountId: "account-1")
        let sdk = createTestPushNotificationSdk(storage: storage, handleRequest: failIfCalled)

        #expect(await sdk.listEnrollments().isEmpty)
    }
}
