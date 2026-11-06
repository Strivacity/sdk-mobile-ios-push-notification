import CryptoKit
import Foundation
@testable import PushNotification
import Testing

/// Exercises the log lines `DefaultPushNotificationStorage` emits through `Logging`.
struct DefaultPushNotificationStorageLoggingTests {
    let keychain = InMemoryKeychainItems()
    let logging = RecordingLogging()
    let issuer = "https://issuer.example.com"
    let accountId = "account-1"

    func storage(allowSoftwareBackedKeys: Bool = true) -> DefaultPushNotificationStorage {
        DefaultPushNotificationStorage(
            allowSoftwareBackedKeys: allowSoftwareBackedKeys,
            keychain: keychain,
            logging: logging
        )
    }

    @Test(.enabled(if: !SecureEnclave.isAvailable))
    func creatingASoftwareHeldKeyBecauseTheSecureEnclaveIsUnavailableIsLogged() async throws {
        _ = try await storage().createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)

        #expect(logging.lines == [
            "INFO The Secure Enclave is unavailable on this device; creating a software-held key",
        ])
    }

    @Test(.enabled(if: !SecureEnclave.isAvailable))
    func aRefusedSoftwareBackedKeyIsLoggedAsAnError() async throws {
        await #expect(throws: PushNotificationError.self) {
            try await storage(allowSoftwareBackedKeys: false)
                .createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)
        }

        #expect(logging.lines == [
            "ERROR The key could only be created in software, and software-backed keys are not allowed",
        ])
    }

    @Test func aFailureListingEnrollmentsIsLoggedAndReportsNone() async {
        keychain.fail(.read)

        let enrollments = await storage().listEnrollments()

        #expect(enrollments.isEmpty)
        #expect(logging.lines.count == 1)
        #expect(logging.lines.first?.hasPrefix("ERROR Enrollments could not be listed (") == true)
        #expect(logging.lines.first?.hasSuffix("); reporting none") == true)
    }

    @Test func anUnreadableRecordIsLoggedAndSkipped() async {
        keychain.store(
            Data("not a stored key".utf8),
            account: KeyAlias.of(issuer: issuer, accountId: accountId, keyId: "key-1")
        )

        let enrollments = await storage().listEnrollments()

        #expect(enrollments.isEmpty)
        #expect(logging.lines.count == 1)
        #expect(logging.lines.first?.hasPrefix("WARN Enrollment record unreadable, skipped (") == true)
        #expect(logging.lines.first?.contains("not a stored key") == false)
    }

    @Test func aFailureRemovingAnEnrollmentIsLoggedAndRethrown() async throws {
        _ = try await storage().createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)
        keychain.fail(.delete)

        await #expect(throws: (any Error).self) {
            try await storage().removeEnrollment(issuer: issuer, accountId: accountId)
        }

        #expect(logging.lines.contains { $0.hasPrefix("ERROR The enrollment could not be removed (") })
    }

    @Test func severalKeysForOneEnrollmentAreLoggedAsAWarning() async throws {
        let first = storage()
        _ = try await first.createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)
        let existing = try #require(keychain.all().first)
        keychain.store(existing.value, account: KeyAlias.of(issuer: issuer, accountId: accountId, keyId: "key-2"))

        _ = try await first.getPublicKey(issuer: issuer, accountId: accountId)

        #expect(logging.lines.contains("WARN Several keys exist for one enrollment; using the first"))
    }
}
