/// Everything the SDK persists: each enrollment's key and the record of the enrollment itself. A
/// replaceable extension point — the SDK ships `DefaultPushNotificationStorage`, backed by the
/// Keychain.
///
/// A replacement must:
///
/// - use a key id unique to the key, not to the account;
/// - return the signature from `createSignature` as a base64url string;
/// - return a `Jwk` holding only the public half — see `Jwk.privateMembers`;
/// - keep each enrollment's key and record together, so that one is never left without the other;
/// - throw `PushNotificationError.storageFailure` for a failure — the SDK rethrows it unchanged.
public protocol PushNotificationStorage: Sendable {
    // MARK: - Keys

    /// The public key currently in use for this issuer and account, or `nil` if none is stored.
    ///
    /// Only a single key exists for an issuer and account combination.
    func getPublicKey(issuer: String, accountId: String) async throws -> Jwk?

    /// Signs `data` with the key of this id, returning the signature as a base64url string.
    ///
    /// `issuer` and `accountId` identify the same key `getPublicKey` returned it for.
    ///
    /// - Throws: `PushNotificationError.notEnrolled` if no enrollment is recorded for this issuer
    ///   and account — checked first. `PushNotificationError.storageFailure` if an enrollment is
    ///   recorded but no key of that id is stored.
    func createSignature(issuer: String, accountId: String, keyId: String, data: String) async throws -> String

    // MARK: - Enrollments

    /// Generates a new keypair for this issuer and account, records the enrollment it belongs to,
    /// and returns the key's public half. The recorded enrollment's `keyId` is the returned key's
    /// `kid`.
    ///
    /// The SDK calls this before the backend has accepted the enrollment, and calls
    /// `removeEnrollment` if the backend refuses it.
    ///
    /// The SDK calls `removeEnrollment` for this issuer and account first, so an existing key here
    /// means a concurrent call created it in the meantime.
    ///
    /// - Throws: `PushNotificationError.alreadyEnrolled` if a key already exists for this issuer
    ///   and account — including when lost to a race against a concurrent call for the same
    ///   issuer and account. The default implementation does not synchronize between concurrent
    ///   calls.
    func createEnrollment(issuer: String, accountId: String, userName: String?, deviceName: String?) async throws -> Jwk

    /// Every enrollment currently recorded. A read failure degrades to an empty list.
    func listEnrollments() async -> [Enrollment]

    /// Removes every key and enrollment record held for this issuer and account. Silently does
    /// nothing if none is stored.
    func removeEnrollment(issuer: String, accountId: String) async throws
}
