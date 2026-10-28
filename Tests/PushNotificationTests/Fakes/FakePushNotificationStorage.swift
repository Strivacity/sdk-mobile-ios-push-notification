@testable import PushNotification

/// In-memory `PushNotificationStorage` fake. Keys are ES256 with predictable, incrementing ids.
actor FakePushNotificationStorage: PushNotificationStorage {
    private var entries: [Pair: Entry] = [:]
    private var nextKeyId = 1

    func getPublicKey(issuer: String, accountId: String) async throws -> Jwk? {
        entries[Pair(issuer, accountId)]?.key
    }

    func createSignature(issuer: String, accountId: String, keyId: String, data: String) async throws -> String {
        guard let entry = entries[Pair(issuer, accountId)], entry.enrollment != nil else {
            throw PushNotificationError.notEnrolled(accountId: accountId)
        }
        guard entry.key.kid == keyId else {
            throw TestFailure("No key is stored for this key id")
        }
        // A real signature is base64url, per this method's contract — encoded here too, so a
        // signed-JWT's segments never accidentally pick up a literal '.' from the signing input.
        return Base64Url.encode("signature-of(\(data))")
    }

    func createEnrollment(issuer: String, accountId: String, userName: String?,
                          deviceName: String?) async throws -> Jwk {
        guard entries[Pair(issuer, accountId)] == nil else {
            throw PushNotificationError.alreadyEnrolled(issuer: issuer, accountId: accountId)
        }

        let key = newKey()
        let enrollment = Enrollment(
            issuer: issuer,
            accountId: accountId,
            keyId: key.kid,
            userName: userName,
            deviceName: deviceName
        )
        entries[Pair(issuer, accountId)] = Entry(key: key, enrollment: enrollment)
        return key
    }

    func listEnrollments() async -> [Enrollment] {
        entries.values.compactMap(\.enrollment)
    }

    func removeEnrollment(issuer: String, accountId: String) async throws {
        entries[Pair(issuer, accountId)] = nil
    }

    /// Stores a key with no enrollment record for this issuer and account.
    func storeKeyWithoutEnrollment(issuer: String, accountId: String) -> Jwk {
        let key = newKey()
        entries[Pair(issuer, accountId)] = Entry(key: key, enrollment: nil)
        return key
    }

    private func newKey() -> Jwk {
        let key = Jwk(
            kid: "key-\(nextKeyId)",
            alg: Jwk.algorithmES256,
            members: ["kty": "EC", "crv": "P-256", "x": "x-coord", "y": "y-coord"]
        )
        nextKeyId += 1
        return key
    }

    private struct Entry {
        let key: Jwk
        let enrollment: Enrollment?
    }

    private struct Pair: Hashable {
        let issuer: String
        let accountId: String

        init(_ issuer: String, _ accountId: String) {
            self.issuer = issuer
            self.accountId = accountId
        }
    }
}
