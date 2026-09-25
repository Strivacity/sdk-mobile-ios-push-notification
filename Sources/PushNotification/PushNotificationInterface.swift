/// Everything the SDK does.
///
/// Does not scan QR codes, obtain or refresh the push token, own a messaging service, post
/// notifications, or render UI — those are the host app's responsibility.
///
/// Whatever the storage throws is rethrown unchanged — `storageFailure` with the default storage.
public protocol PushNotificationInterface: Sendable {
    /// Enrolls this device for the account named in `grant`.
    ///
    /// The key and enrollment record are stored before the backend is called, and removed again if
    /// it fails. If the app is terminated mid-call the enrollment stays recorded; `unenrollDevice`
    /// removes it.
    ///
    /// - Parameter deviceToken: the current push token, owned by the app.
    /// - Parameter deviceTokenType: what kind of token `deviceToken` is.
    /// - Parameter deviceName: a label for this device, 1-64 characters after trimming.
    /// - Throws: `invalidDeviceName`, `invalidIssuer`, `alreadyEnrolled` (un-enroll first).
    ///   `storageFailure` or `softwareBackedKey` from storage. `unsupportedAlgorithm` or
    ///   `storageFailure` for a key the SDK can't accept. `enrollmentRejected` (not retryable;
    ///   obtain a fresh grant) or `networkFailure` from the backend. A failed rollback replaces the
    ///   error that caused it.
    func enrollDevice(
        grant: EnrollmentGrant,
        deviceToken: String,
        deviceTokenType: DeviceTokenType,
        deviceName: String
    ) async throws -> Enrollment

    /// Removes this device's enrollment for an account.
    ///
    /// The backend is called first. The local key and record are then removed whether or not that
    /// succeeded, so a backend failure never blocks re-enrolling — though the backend may still
    /// hold the enrollment, with no key left to retry.
    ///
    /// - Throws: `invalidIssuer`, `notEnrolled`. `storageFailure` looking up or signing with the
    ///   key, before the backend is contacted: nothing has changed. Or removing locally: it
    ///   replaces any backend failure, which is lost. `unenrollmentRejected` or `networkFailure`,
    ///   thrown after the local removal.
    func unenrollDevice(issuer: String, accountId: String) async throws

    /// Whether an enrollment is recorded for this issuer and account — the check `enrollDevice`
    /// makes. An unreadable store reads as not enrolled.
    ///
    /// - Throws: `invalidIssuer`.
    func hasEnrollment(issuer: String, accountId: String) async throws -> Bool

    /// Every enrollment this device holds, across issuers and accounts, including ones the app
    /// never initiated. Lets the app decide how to report a rotated push token, via
    /// `updateDeviceToken`.
    ///
    /// Doesn't throw: an unreadable store reads as empty.
    func listEnrollments() async -> [Enrollment]

    /// Reports a new push token for an existing enrollment. Call it once per enrollment when the
    /// platform delivers a new token — the SDK doesn't detect rotation.
    ///
    /// - Throws: `invalidIssuer`, `notEnrolled`, `storageFailure` looking up or signing with the
    ///   key. `tokenUpdateRejected` or `networkFailure` from the backend.
    func updateDeviceToken(
        issuer: String,
        accountId: String,
        deviceToken: String,
        deviceTokenType: DeviceTokenType
    ) async throws

    /// Whether this push payload is a challenge for a key this device holds.
    ///
    /// Returns `false`, not an error, for a missing or unrecognised envelope (version included) or a
    /// malformed issuer — both come from an untrusted payload.
    ///
    /// - Throws: `storageFailure` looking up the key.
    func canHandleMessage(_ messageData: [String: String]?) async throws -> Bool

    /// Fetches the challenge the payload points at. Makes a network call. Call `canHandleMessage`
    /// first.
    ///
    /// - Throws: `invalidIssuer`; `notEnrolled` if no key is held for the issuer and account the
    ///   payload names. `storageFailure` looking up the key. `challengeUnavailable` (no usable
    ///   envelope, backend refusal, or a response it can't read), `unsupportedChallengeType` or
    ///   `networkFailure` from the backend.
    func handleMessage(_ messageData: [String: String]?) async throws -> Challenge

    /// Submits the user's answer. A recorded refusal returns `ResolutionResult.notOk`; it isn't an
    /// error. The resolution's issuer is used as given, not normalised.
    ///
    /// - Throws: `notEnrolled`, `storageFailure` looking up or signing with the key.
    ///   `networkFailure`, or `challengeUnavailable` for a backend response that is neither
    ///   acceptance nor denial.
    func resolveChallenge(_ resolution: ChallengeResolution) async throws -> ResolutionResult
}
