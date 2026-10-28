import CryptoKit
import Foundation

/// The shipped `PushNotificationStorage`: P-256 keys backed by the Secure Enclave where available,
/// each stored in the Keychain together with the enrollment it belongs to.
///
/// Needs no extra entitlement or setup. Each enrollment is a single Keychain item, aliased per
/// `KeyAlias`, holding both the key (or, when falling back, its software-held raw representation)
/// and the enrollment's details. The two therefore share one lifecycle: both survive an app
/// reinstall, neither is restored to another device, and creating or removing an enrollment is a
/// single Keychain write.
///
/// Availability is checked once, upfront, per `createEnrollment` call: `SecureEnclave` and a plain
/// software `P256.Signing.PrivateKey` are different Swift types with no shared "generate then
/// inspect" API, so which one to create has to be decided before generation, not after.
///
/// No explicit access control is set on the Secure Enclave key: CryptoKit's default requires no
/// user presence.
public struct DefaultPushNotificationStorage: PushNotificationStorage {
    private let allowSoftwareBackedKeys: Bool
    private let keychain: KeychainItems

    /// - Parameter allowSoftwareBackedKeys: if `false` (default), a key that could only be created
    ///   in software is refused. The Simulator has no Secure Enclave at all.
    public init(allowSoftwareBackedKeys: Bool = false) {
        self.init(allowSoftwareBackedKeys: allowSoftwareBackedKeys, keychain: SystemKeychainItems())
    }

    init(allowSoftwareBackedKeys: Bool, keychain: KeychainItems) {
        self.allowSoftwareBackedKeys = allowSoftwareBackedKeys
        self.keychain = keychain
    }

    // MARK: - Keys

    public func getPublicKey(issuer: String, accountId: String) async throws -> Jwk? {
        // Only a single key should exist for an issuer and account combination.
        guard let item = try items(for: issuer, accountId: accountId).first else {
            return nil
        }

        return try Jwk(p256PublicKey: item.storedKey.publicKeyData(), kid: KeyAlias.keyIdOf(item.alias))
    }

    public func createSignature(issuer: String, accountId: String, keyId: String, data: String) async throws -> String {
        // Checked first: with no readable item stored the account isn't enrolled, whatever else the
        // Keychain holds.
        guard try !items(for: issuer, accountId: accountId).isEmpty else {
            throw PushNotificationError.notEnrolled(accountId: accountId)
        }

        let alias = KeyAlias.of(issuer: issuer, accountId: accountId, keyId: keyId)
        guard let storedData = try keychain.data(account: alias) else {
            throw PushNotificationError.storageFailure(message: "No key is stored for this key id", cause: nil)
        }

        let storedKey = try JSONDecoder().decode(StoredKey.self, from: storedData)
        let message = Data(data.utf8)
        let signature: P256.Signing.ECDSASignature =
            switch storedKey.kind {
            case .secureEnclave:
                try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: storedKey.data).signature(for: message)
            case .software:
                try P256.Signing.PrivateKey(rawRepresentation: storedKey.data).signature(for: message)
            }

        return Base64Url.encode(signature.rawRepresentation)
    }

    // MARK: - Enrollments

    public func createEnrollment(
        issuer: String,
        accountId: String,
        userName: String?,
        deviceName: String?
    ) async throws -> Jwk {
        // Not a single atomic operation against the Keychain — check narrows the race window
        // against a concurrent call for the same issuer and account, but doesn't eliminate it.
        guard try items(for: issuer, accountId: accountId).isEmpty else {
            throw PushNotificationError.alreadyEnrolled(issuer: issuer, accountId: accountId)
        }

        let keyId = try KeyAlias.newKeyId()
        let alias = KeyAlias.of(issuer: issuer, accountId: accountId, keyId: keyId)
        let record = EnrollmentRecord(
            Enrollment(issuer: issuer, accountId: accountId, keyId: keyId, userName: userName, deviceName: deviceName)
        )

        let storedKey: StoredKey
        let publicKeyData: Data

        if SecureEnclave.isAvailable {
            let privateKey = try SecureEnclave.P256.Signing.PrivateKey()
            storedKey = StoredKey(kind: .secureEnclave, data: privateKey.dataRepresentation, enrollment: record)
            publicKeyData = privateKey.publicKey.x963Representation
        } else if allowSoftwareBackedKeys {
            let privateKey = P256.Signing.PrivateKey()
            storedKey = StoredKey(kind: .software, data: privateKey.rawRepresentation, enrollment: record)
            publicKeyData = privateKey.publicKey.x963Representation
        } else {
            throw PushNotificationError.softwareBackedKey
        }

        try keychain.add(JSONEncoder().encode(storedKey), account: alias)
        return Jwk(p256PublicKey: publicKeyData, kid: keyId)
    }

    public func listEnrollments() async -> [Enrollment] {
        let items = (try? items(where: KeyAlias.isOurs)) ?? []
        return items.map { $0.storedKey.enrollment.toEnrollment }
    }

    /// Also removes an item stored under this issuer and account whose contents can't be read.
    public func removeEnrollment(issuer: String, accountId: String) async throws {
        let prefix = KeyAlias.prefixFor(issuer: issuer, accountId: accountId)
        for alias in try keychain.all().keys where alias.hasPrefix(prefix) {
            try keychain.delete(account: alias)
        }
    }

    /// Every readable item stored for this issuer and account.
    private func items(for issuer: String, accountId: String) throws -> [KeychainItem] {
        let prefix = KeyAlias.prefixFor(issuer: issuer, accountId: accountId)
        return try items(where: { $0.hasPrefix(prefix) })
    }

    /// Every readable item whose alias `isIncluded` accepts — Keychain queries have no
    /// prefix-match operator, so this fetches every one of the SDK's items and filters
    /// client-side.
    private func items(where isIncluded: (String) -> Bool) throws -> [KeychainItem] {
        try keychain.all().compactMap { alias, data in
            guard isIncluded(alias), let storedKey = try? JSONDecoder().decode(StoredKey.self, from: data) else {
                return nil
            }

            return KeychainItem(alias: alias, storedKey: storedKey)
        }
    }
}

/// One Keychain item matching a scan (`items(where:)`).
private struct KeychainItem {
    let alias: String
    let storedKey: StoredKey
}

/// What's actually persisted per enrollment: the key, which CryptoKit representation its `data`
/// is so it can be reconstructed into the right type later, and the enrollment it belongs to.
private struct StoredKey: Codable {
    enum Kind: String, Codable {
        case secureEnclave
        case software
    }

    let kind: Kind
    let data: Data
    let enrollment: EnrollmentRecord

    func publicKeyData() throws -> Data {
        switch kind {
        case .secureEnclave:
            try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data).publicKey.x963Representation
        case .software:
            try P256.Signing.PrivateKey(rawRepresentation: data).publicKey.x963Representation
        }
    }
}

/// The persisted shape of an enrollment, kept separate from the public `Enrollment` domain type.
/// Tolerant of a record from an older or newer SDK version: unknown keys are ignored
/// (`JSONDecoder`'s default behavior), and `userName`/`deviceName` default to `nil` if absent.
private struct EnrollmentRecord: Codable {
    let issuer: String
    let accountId: String
    let keyId: String
    let userName: String?
    let deviceName: String?

    init(_ enrollment: Enrollment) {
        issuer = enrollment.issuer
        accountId = enrollment.accountId
        keyId = enrollment.keyId
        userName = enrollment.userName
        deviceName = enrollment.deviceName
    }

    var toEnrollment: Enrollment {
        Enrollment(issuer: issuer, accountId: accountId, keyId: keyId, userName: userName, deviceName: deviceName)
    }
}
