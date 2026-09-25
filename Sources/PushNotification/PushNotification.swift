import Foundation

/// The SDK.
///
/// One instance serves every issuer a device is enrolled against; the issuer is supplied with
/// each grant, challenge, and resolution. Instances are app-scoped and are not closed.
public struct PushNotification: PushNotificationInterface {
    private let storage: PushNotificationStorage
    private let client: PushNotificationClient

    public init(storage: PushNotificationStorage) {
        self.init(storage: storage, client: PushNotificationClient())
    }

    init(storage: PushNotificationStorage, client: PushNotificationClient) {
        self.storage = storage
        self.client = client
    }

    public func enrollDevice(
        grant: EnrollmentGrant,
        deviceToken: String,
        deviceTokenType: DeviceTokenType,
        deviceName: String
    ) async throws -> Enrollment {
        try validateDeviceName(deviceName)
        let issuer = try normalizeIssuer(grant.issuer)

        if await isEnrolled(normalizedIssuer: issuer, accountId: grant.accountId) {
            throw PushNotificationError.alreadyEnrolled(issuer: issuer, accountId: grant.accountId)
        }

        try await storage.removeEnrollment(issuer: issuer, accountId: grant.accountId)

        // Not atomic with the check above — a concurrent enrollDevice call for the same issuer
        // and account can still win the race. createEnrollment's own guard against that throws
        // .alreadyEnrolled itself, so both the fast-path miss and the race-loser path surface the
        // same typed error with no extra handling needed here.
        let key = try await storage.createEnrollment(
            issuer: issuer,
            accountId: grant.accountId,
            userName: grant.displayUserName,
            deviceName: deviceName
        )
        try await enroll(
            normalizedIssuer: issuer,
            grant: grant,
            key: key,
            deviceToken: deviceToken,
            deviceTokenType: deviceTokenType,
            deviceName: deviceName
        )

        return Enrollment(
            issuer: issuer,
            accountId: grant.accountId,
            keyId: key.kid,
            userName: grant.displayUserName,
            deviceName: deviceName
        )
    }

    public func unenrollDevice(issuer: String, accountId: String) async throws {
        let normalized = try normalizeIssuer(issuer)
        guard let key = try await storage.getPublicKey(issuer: normalized, accountId: accountId) else {
            throw PushNotificationError.notEnrolled(accountId: accountId)
        }

        let assertion = try await sign(normalizedIssuer: normalized, accountId: accountId, key: key) {
            [Claim.accountId: accountId]
        }

        // The local removal always runs, even if the backend call fails — see the interface doc.
        var backendFailure: Error?
        do {
            try await client.unenroll(normalizedIssuer: normalized, unenrollJwt: assertion)
        } catch {
            backendFailure = error
        }

        try await storage.removeEnrollment(issuer: normalized, accountId: accountId)

        if let backendFailure {
            throw backendFailure
        }
    }

    public func updateDeviceToken(
        issuer: String,
        accountId: String,
        deviceToken: String,
        deviceTokenType: DeviceTokenType
    ) async throws {
        let normalized = try normalizeIssuer(issuer)
        guard let key = try await storage.getPublicKey(issuer: normalized, accountId: accountId) else {
            throw PushNotificationError.notEnrolled(accountId: accountId)
        }

        let assertion = try await sign(normalizedIssuer: normalized, accountId: accountId, key: key) {
            [
                Claim.accountId: accountId,
                Claim.deviceTokenType: deviceTokenType.wireValue,
                Claim.deviceToken: deviceToken,
            ]
        }

        try await client.updateToken(normalizedIssuer: normalized, updateTokenJwt: assertion)
    }

    public func hasEnrollment(issuer: String, accountId: String) async throws -> Bool {
        try await isEnrolled(normalizedIssuer: normalizeIssuer(issuer), accountId: accountId)
    }

    public func listEnrollments() async -> [Enrollment] {
        await storage.listEnrollments()
    }

    public func canHandleMessage(_ messageData: [String: String]?) async throws -> Bool {
        // A malformed issuer is swallowed to `false` here — unlike `hasEnrollment`'s or
        // `handleMessage`'s unguarded normalization — because it comes from an untrusted push
        // payload rather than a direct argument. A storage failure while looking up the
        // key is not swallowed the same way; it still throws.
        guard let envelope = PushEnvelope.parse(messageData), let issuer = try? normalizeIssuer(envelope.issuer) else {
            return false
        }

        return try await storage.getPublicKey(issuer: issuer, accountId: envelope.accountId) != nil
    }

    public func handleMessage(_ messageData: [String: String]?) async throws -> Challenge {
        guard let envelope = PushEnvelope.parse(messageData) else {
            throw PushNotificationError.challengeUnavailable(
                message: "Message carries no challenge this SDK version can handle",
                status: nil,
                cause: nil
            )
        }

        let issuer = try normalizeIssuer(envelope.issuer)
        guard try await storage.getPublicKey(issuer: issuer, accountId: envelope.accountId) != nil else {
            throw PushNotificationError.notEnrolled(accountId: envelope.accountId)
        }

        let response = try await client.challenge(normalizedIssuer: issuer, challengeId: envelope.challengeId)
        return try response.toDomain(envelope: envelope, normalizedIssuer: issuer)
    }

    public func resolveChallenge(_ resolution: ChallengeResolution) async throws -> ResolutionResult {
        guard
            let key = try await storage.getPublicKey(
                issuer: resolution.issuer,
                accountId: resolution.accountId
            ) else {
            throw PushNotificationError.notEnrolled(accountId: resolution.accountId)
        }

        let assertion = try await sign(
            normalizedIssuer: resolution.issuer,
            accountId: resolution.accountId,
            key: key
        ) {
            [
                Claim.challengeId: resolution.challengeId,
                Claim.challenge: resolution.challengeValue,
                Claim.action: resolution.action,
            ]
        }

        let accepted = try await client.resolve(
            normalizedIssuer: resolution.issuer,
            challengeId: resolution.challengeId,
            resolutionJwt: assertion
        )
        return accepted ? .ok : .notOk
    }

    // MARK: - Private helpers

    /// Rolls the key and its enrollment record back if enrollment fails.
    private func enroll(
        normalizedIssuer: String,
        grant: EnrollmentGrant,
        key: Jwk,
        deviceToken: String,
        deviceTokenType: DeviceTokenType,
        deviceName: String
    ) async throws {
        do {
            try checkPrivateKeyMaterial(key)

            try await client.enroll(
                normalizedIssuer: normalizedIssuer,
                oneTimeToken: grant.oneTimeToken,
                request: EnrollRequest(
                    platform: Platforms.ios,
                    deviceTokenType: deviceTokenType.wireValue,
                    deviceToken: deviceToken,
                    deviceName: deviceName,
                    publicKey: key.wireObject
                )
            )
        } catch {
            // Broad catch deliberately: any failure here — not just a rejected/network
            // PushNotificationError, but also e.g. a request-encoding failure building
            // EnrollRequest — must still roll back the freshly generated key. Not yet covered by
            // a unit test.
            try await storage.removeEnrollment(issuer: normalizedIssuer, accountId: grant.accountId)
            throw error
        }
    }

    private func sign(
        normalizedIssuer: String,
        accountId: String,
        key: Jwk,
        claims: () -> [String: String]
    ) async throws -> String {
        let payloadData = try JSONEncoder().encode(claims())
        guard let payload = String(bytes: payloadData, encoding: .utf8) else {
            throw PushNotificationError.storageFailure(message: "JWT payload could not be encoded", cause: nil)
        }

        return try await buildSignedJwt(keyId: key.kid, algorithm: key.alg, payload: payload) { signingInput in
            try await storage.createSignature(
                issuer: normalizedIssuer,
                accountId: accountId,
                keyId: key.kid,
                data: signingInput
            )
        }
    }

    /// Whether storage records an enrollment for this issuer and account.
    private func isEnrolled(normalizedIssuer: String, accountId: String) async -> Bool {
        await storage.listEnrollments().contains {
            $0.issuer == normalizedIssuer && $0.accountId == accountId
        }
    }

    /// Validates a key returned by `PushNotificationStorage.createEnrollment` before it reaches the backend.
    private func checkPrivateKeyMaterial(_ key: Jwk) throws {
        let privateMembers = Set(key.members.keys).intersection(Jwk.privateMembers)
        guard privateMembers.isEmpty else {
            throw PushNotificationError.storageFailure(
                message: "Storage supplied a public key still carrying private members: \(privateMembers.sorted())",
                cause: nil
            )
        }

        guard Self.acceptedAlgorithms.contains(key.alg) else {
            throw PushNotificationError.unsupportedAlgorithm(algorithm: key.alg, accepted: Self.acceptedAlgorithms)
        }
    }

    /// Accepted signing algorithms.
    private static let acceptedAlgorithms: Set<String> = [Jwk.algorithmES256]

    private enum Claim {
        // Field names are placeholders pending the backend contract.
        static let challengeId = "challengeId"
        static let challenge = "challenge"
        static let action = "action"
        static let accountId = "accountId"
        static let deviceToken = "deviceToken"
        static let deviceTokenType = "deviceTokenType"
    }
}
