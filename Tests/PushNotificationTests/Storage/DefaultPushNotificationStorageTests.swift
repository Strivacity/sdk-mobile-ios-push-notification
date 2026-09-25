import CryptoKit
import Foundation
@testable import PushNotification
import Testing

/// Exercises `DefaultPushNotificationStorage` directly, against an in-memory fake of the Keychain
/// and with software keys allowed, since the Simulator has no Secure Enclave.
struct DefaultPushNotificationStorageTests {
    let keychain = InMemoryKeychainItems()
    let issuer = "https://issuer.example.com"
    let accountId = "account-1"

    var storage: DefaultPushNotificationStorage {
        DefaultPushNotificationStorage(allowSoftwareBackedKeys: true, keychain: keychain)
    }

    // --- creating ---

    @Test func listsACreatedEnrollmentWithItsKeyIdAndDetails() async throws {
        let key = try await storage.createEnrollment(
            issuer: issuer,
            accountId: accountId,
            userName: "Jane",
            deviceName: "My Phone"
        )

        #expect(await storage.listEnrollments() == [Enrollment(
            issuer: issuer,
            accountId: accountId,
            keyId: key.kid,
            userName: "Jane",
            deviceName: "My Phone"
        )])
    }

    @Test func returnsTheCreatedKeyFromGetPublicKey() async throws {
        let key = try await storage.createEnrollment(
            issuer: issuer,
            accountId: accountId,
            userName: nil,
            deviceName: nil
        )

        #expect(try await storage.getPublicKey(issuer: issuer, accountId: accountId) == key)
    }

    @Test func returnsAnES256PublicKeyWithoutPrivateMembers() async throws {
        let key = try await storage.createEnrollment(
            issuer: issuer,
            accountId: accountId,
            userName: nil,
            deviceName: nil
        )

        #expect(key.alg == Jwk.algorithmES256)
        #expect(Set(key.members.keys).isDisjoint(with: Jwk.privateMembers))
    }

    @Test func storesTheKeyAndTheEnrollmentInOneKeychainItem() async throws {
        let key = try await storage.createEnrollment(
            issuer: issuer,
            accountId: accountId,
            userName: nil,
            deviceName: nil
        )

        #expect(keychain.accounts == [KeyAlias.of(issuer: issuer, accountId: accountId, keyId: key.kid)])
    }

    @Test func throwsAlreadyEnrolledWhenAnEnrollmentExistsForTheIssuerAndAccount() async throws {
        _ = try await storage.createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)

        let failure = try await #require(throws: PushNotificationError.self) {
            try await storage.createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)
        }
        #expect(failure.code == "already_enrolled")
    }

    @Test func storesNothingWhenWritingToTheKeychainFails() async throws {
        keychain.fail(.add)

        await #expect(throws: TestFailure.self) {
            try await storage.createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)
        }
        #expect(keychain.accounts.isEmpty)
    }

    @Test(.enabled(if: !SecureEnclave.isAvailable))
    func throwsSoftwareBackedKeyWhenOnlyASoftwareKeyCouldBeCreatedAndThatIsNotAllowed() async throws {
        let strictStorage = DefaultPushNotificationStorage(allowSoftwareBackedKeys: false, keychain: keychain)

        let failure = try await #require(throws: PushNotificationError.self) {
            try await strictStorage.createEnrollment(
                issuer: issuer,
                accountId: accountId,
                userName: nil,
                deviceName: nil
            )
        }
        #expect(failure.code == "software_backed_key")
        #expect(keychain.accounts.isEmpty)
    }

    // --- listing ---

    @Test func listsEnrollmentsAcrossIssuersAndAccounts() async throws {
        _ = try await storage.createEnrollment(issuer: issuer, accountId: "account-1", userName: nil, deviceName: nil)
        _ = try await storage.createEnrollment(issuer: issuer, accountId: "account-2", userName: nil, deviceName: nil)
        _ = try await storage.createEnrollment(
            issuer: "https://a-different-issuer.example.com",
            accountId: "account-1",
            userName: nil,
            deviceName: nil
        )

        #expect(await storage.listEnrollments().count == 3)
    }

    @Test func omitsAnItemWhoseContentsCannotBeRead() async throws {
        keychain.store(
            Data("not json".utf8),
            account: KeyAlias.of(issuer: issuer, accountId: "account-1", keyId: "key-1")
        )
        _ = try await storage.createEnrollment(issuer: issuer, accountId: "account-2", userName: nil, deviceName: nil)

        #expect(await storage.listEnrollments().map(\.accountId) == ["account-2"])
    }

    @Test func returnsAnEmptyListWhenReadingTheKeychainFails() async throws {
        _ = try await storage.createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)
        keychain.fail(.read)

        #expect(await storage.listEnrollments().isEmpty)
    }

    // --- signing ---

    @Test func createsASignatureTheReturnedPublicKeyVerifies() async throws {
        let key = try await storage.createEnrollment(
            issuer: issuer,
            accountId: accountId,
            userName: nil,
            deviceName: nil
        )

        let signature = try await storage.createSignature(
            issuer: issuer,
            accountId: accountId,
            keyId: key.kid,
            data: "signing-input"
        )

        let publicKey = try p256PublicKey(from: key)
        let signatureBytes = try #require(Base64Url.decode(signature))
        let ecdsaSignature = try P256.Signing.ECDSASignature(rawRepresentation: signatureBytes)
        #expect(publicKey.isValidSignature(ecdsaSignature, for: Data("signing-input".utf8)))
    }

    @Test func throwsStorageFailureWhenSigningWithAnUnknownKeyId() async throws {
        _ = try await storage.createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)

        let failure = try await #require(throws: PushNotificationError.self) {
            try await storage.createSignature(issuer: issuer, accountId: accountId, keyId: "unknown", data: "data")
        }
        #expect(failure.code == "storage_failure")
    }

    @Test func throwsNotEnrolledWhenSigningForAnAccountThatIsNotEnrolled() async throws {
        let failure = try await #require(throws: PushNotificationError.self) {
            try await storage.createSignature(issuer: issuer, accountId: accountId, keyId: "unknown", data: "data")
        }
        #expect(failure.code == "not_enrolled")
    }

    @Test func throwsNotEnrolledWhenSigningWithAKeyIdUnderADifferentAccount() async throws {
        let key = try await storage.createEnrollment(
            issuer: issuer,
            accountId: accountId,
            userName: nil,
            deviceName: nil
        )

        let failure = try await #require(throws: PushNotificationError.self) {
            try await storage.createSignature(issuer: issuer, accountId: "other-account", keyId: key.kid, data: "data")
        }
        guard case let .notEnrolled(failedAccountId) = failure else {
            Issue.record("expected .notEnrolled, got \(failure)")
            return
        }
        #expect(failedAccountId == "other-account")
    }

    // --- removing ---

    @Test func removesBothTheKeyAndTheEnrollment() async throws {
        _ = try await storage.createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)

        try await storage.removeEnrollment(issuer: issuer, accountId: accountId)

        #expect(try await storage.getPublicKey(issuer: issuer, accountId: accountId) == nil)
        #expect(await storage.listEnrollments().isEmpty)
    }

    @Test func removesOnlyTheGivenIssuerAndAccount() async throws {
        _ = try await storage.createEnrollment(issuer: issuer, accountId: "account-1", userName: nil, deviceName: nil)
        _ = try await storage.createEnrollment(issuer: issuer, accountId: "account-2", userName: nil, deviceName: nil)

        try await storage.removeEnrollment(issuer: issuer, accountId: "account-1")

        #expect(await storage.listEnrollments().map(\.accountId) == ["account-2"])
    }

    @Test func removesAnItemWhoseContentsCannotBeRead() async throws {
        keychain.store(
            Data("not json".utf8),
            account: KeyAlias.of(issuer: issuer, accountId: accountId, keyId: "key-1")
        )

        try await storage.removeEnrollment(issuer: issuer, accountId: accountId)

        #expect(keychain.accounts.isEmpty)
    }

    @Test func removingWhenNothingIsStoredDoesNothing() async throws {
        try await storage.removeEnrollment(issuer: issuer, accountId: accountId)

        #expect(keychain.accounts.isEmpty)
    }

    @Test func throwsWhenRemovingFromTheKeychainFails() async throws {
        _ = try await storage.createEnrollment(issuer: issuer, accountId: accountId, userName: nil, deviceName: nil)
        keychain.fail(.delete)

        await #expect(throws: TestFailure.self) {
            try await storage.removeEnrollment(issuer: issuer, accountId: accountId)
        }
    }

    private func p256PublicKey(from key: Jwk) throws -> P256.Signing.PublicKey {
        let x = try #require(key.members["x"].flatMap(Base64Url.decode))
        let y = try #require(key.members["y"].flatMap(Base64Url.decode))
        return try P256.Signing.PublicKey(x963Representation: Data([0x04]) + x + y)
    }
}
