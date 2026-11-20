import Foundation
@testable import PushNotification
import Testing

/// Exercises the log lines the SDK emits through `Logging`.
struct PushNotificationLoggingTests {
    let issuer = "https://tenant-canary.example.com"
    let accountId = "CANARY-ACCOUNT"
    let oneTimeToken = "CANARY-ONE-TIME-TOKEN"
    let deviceToken = "CANARY-DEVICE-TOKEN"
    let deviceName = "CANARY-DEVICE-NAME"
    let userName = "CANARY-USER-NAME"
    let challengeValue = "CANARY-CHALLENGE-VALUE"
    let errorMessage = "CANARY-ERROR-MESSAGE"
    let untrustedVersion = "CANARY-VERSION"

    var secrets: [String] {
        [
            issuer, "tenant-canary", accountId, oneTimeToken, deviceToken, deviceName, userName,
            challengeValue, errorMessage, "aFutureChallengeType", untrustedVersion, "CANARY-METADATA", "://",
        ]
    }

    var grant: EnrollmentGrant {
        EnrollmentGrant(issuer: issuer, oneTimeToken: oneTimeToken, accountId: accountId, displayUserName: userName)
    }

    // --- no sensitive values in any line ---

    @Test func noLogLineCarriesASecretPersonalValueOrURLAcrossTheWholeFlow() async throws {
        let logging = RecordingLogging()
        let sdk = createTestPushNotificationSdk(logging: logging) { request in
            if request.url?.path.hasSuffix("/actions/challenge-1") == true {
                let body = approveDenyResponseBody(metadataJson: #"{"k":"CANARY-METADATA"}"#)
                return respondJson(for: request, body: body)
            }
            return respondSuccess(for: request)
        }

        try await sdk.enrollDevice(
            grant: grant,
            deviceToken: deviceToken,
            deviceTokenType: .fcmToken,
            deviceName: deviceName
        )
        try await sdk.updateDeviceToken(
            issuer: issuer,
            accountId: accountId,
            deviceToken: deviceToken,
            deviceTokenType: .fcmToken
        )
        let message = envelopeMessageData(issuer: issuer, accountId: accountId, challenge: challengeValue)
        _ = try await sdk.canHandleMessage(message)
        let challenge = try await sdk.handleMessage(message)
        guard case let .simple(simple) = challenge else {
            Issue.record("expected a simple challenge")
            return
        }
        _ = try await sdk.resolveChallenge(simple.approve())
        try await sdk.unenrollDevice(issuer: issuer, accountId: accountId)

        expectNoSecrets(in: logging)
    }

    @Test func noLogLineCarriesASecretPersonalValueOrURLAcrossFailurePaths() async throws {
        let logging = RecordingLogging()

        let refusing = createTestPushNotificationSdk(logging: logging) { request in respondFailure(for: request) }
        await #expect(throws: PushNotificationError.self) {
            try await refusing.enrollDevice(
                grant: grant,
                deviceToken: deviceToken,
                deviceTokenType: .fcmToken,
                deviceName: deviceName
            )
        }

        let unreachable = createTestPushNotificationSdk(logging: logging) { _ in throw TestFailure(errorMessage) }
        await #expect(throws: PushNotificationError.self) {
            try await unreachable.enrollDevice(
                grant: grant,
                deviceToken: deviceToken,
                deviceTokenType: .fcmToken,
                deviceName: deviceName
            )
        }

        let enrolled = try await enrolledStorage()
        let unsupported = createTestPushNotificationSdk(storage: enrolled, logging: logging) { request in
            if request.url?.path.contains("/actions/") == true {
                return respondJson(for: request, body: unsupportedChallengeResponseBody())
            }
            return respondSuccess(for: request)
        }
        await #expect(throws: PushNotificationError.self) {
            try await unsupported.handleMessage(
                envelopeMessageData(issuer: issuer, accountId: accountId, challenge: challengeValue)
            )
        }
        _ = try await unsupported.canHandleMessage(
            envelopeMessageData(
                issuer: issuer,
                accountId: accountId,
                challenge: challengeValue,
                version: untrustedVersion
            )
        )
        let truncatedEnvelope = #"{"version":"1","challengeId":"\#(errorMessage)"}"#
        _ = try await unsupported.canHandleMessage([PushEnvelope.key: truncatedEnvelope])
        let issuerWithCredentials = "http://user:\(oneTimeToken)@tenant-canary.example.com"
        await #expect(throws: PushNotificationError.self) {
            try await unsupported.unenrollDevice(issuer: issuerWithCredentials, accountId: accountId)
        }

        #expect(!logging.lines.isEmpty)
        expectNoSecrets(in: logging)
    }

    // --- breadcrumb content ---

    @Test func aSuccessfulEnrollmentLogsItsStartAndItsOutcomeWithTheKeyId() async throws {
        let logging = RecordingLogging()
        let sdk = createTestPushNotificationSdk(logging: logging) { request in respondSuccess(for: request) }

        let enrollment = try await sdk.enrollDevice(
            grant: grant,
            deviceToken: deviceToken,
            deviceTokenType: .fcmToken,
            deviceName: deviceName
        )

        #expect(logging.lines.contains("INFO Enrollment started"))
        #expect(logging.lines.contains("INFO Enrollment succeeded (key \(enrollment.keyId))"))
    }

    @Test func aRefusedEnrollmentLogsTheBackendStatusAndTheRollback() async throws {
        let logging = RecordingLogging()
        let sdk = createTestPushNotificationSdk(logging: logging) { request in respondFailure(for: request) }

        await #expect(throws: PushNotificationError.self) {
            try await sdk.enrollDevice(
                grant: grant,
                deviceToken: deviceToken,
                deviceTokenType: .fcmToken,
                deviceName: deviceName
            )
        }

        #expect(logging.lines.contains("WARN Enrollment refused by the backend (status 400)"))
        #expect(logging.lines.contains {
            $0.hasPrefix("ERROR Enrollment failed (enrollment_rejected); rolling back key")
        })
    }

    @Test func anUnreachableBackendIsLoggedAsAnErrorWithTheTypeNameOnly() async throws {
        let logging = RecordingLogging()
        let sdk = createTestPushNotificationSdk(logging: logging) { _ in throw TestFailure(errorMessage) }

        await #expect(throws: PushNotificationError.self) {
            try await sdk.enrollDevice(
                grant: grant,
                deviceToken: deviceToken,
                deviceTokenType: .fcmToken,
                deviceName: deviceName
            )
        }

        #expect(logging.lines.contains { $0.hasPrefix("ERROR The backend could not be reached during enrollment (") })
    }

    @Test func aURLErrorFromTheBackendIsLoggedWithItsCode() async throws {
        let logging = RecordingLogging()
        let sdk = createTestPushNotificationSdk(logging: logging) { _ in throw URLError(.notConnectedToInternet) }

        await #expect(throws: PushNotificationError.self) {
            try await sdk.enrollDevice(
                grant: grant,
                deviceToken: deviceToken,
                deviceTokenType: .fcmToken,
                deviceName: deviceName
            )
        }

        #expect(logging.lines.contains {
            $0.hasPrefix("ERROR The backend could not be reached during enrollment (")
                && $0.hasSuffix("URLError(-1009))")
        })
    }

    @Test func aCancelledBackendCallIsNotLoggedAsAnUnreachableBackend() async throws {
        let logging = RecordingLogging()
        let sdk = createTestPushNotificationSdk(logging: logging) { _ in throw URLError(.cancelled) }

        await #expect(throws: PushNotificationError.self) {
            try await sdk.enrollDevice(
                grant: grant,
                deviceToken: deviceToken,
                deviceTokenType: .fcmToken,
                deviceName: deviceName
            )
        }

        #expect(!logging.lines.contains { $0.contains("could not be reached") })
    }

    @Test func enrollingAnAlreadyEnrolledAccountIsLoggedAsAWarning() async throws {
        let logging = RecordingLogging()
        let storage = try await enrolledStorage()
        let sdk = createTestPushNotificationSdk(storage: storage, logging: logging) { request in
            respondSuccess(for: request)
        }

        await #expect(throws: PushNotificationError.self) {
            try await sdk.enrollDevice(
                grant: grant,
                deviceToken: deviceToken,
                deviceTokenType: .fcmToken,
                deviceName: deviceName
            )
        }

        #expect(logging.lines.contains("WARN Enrollment refused: this account is already enrolled"))
    }

    @Test func unenrollmentLogsABackendFailureAndThatTheLocalEnrollmentWasRemovedAnyway() async throws {
        let logging = RecordingLogging()
        let storage = try await enrolledStorage()
        let sdk = createTestPushNotificationSdk(storage: storage, logging: logging) { request in
            respondFailure(for: request)
        }

        await #expect(throws: PushNotificationError.self) {
            try await sdk.unenrollDevice(issuer: issuer, accountId: accountId)
        }

        #expect(logging.lines.contains(
            "WARN Un-enrollment failed at the backend (unenrollment_rejected); removing the local enrollment anyway"
        ))
        #expect(logging.lines.contains { $0.hasPrefix("INFO Local enrollment removed") })
    }

    @Test func aResolutionTheBackendDoesNotAcceptIsLoggedAsNotAccepted() async throws {
        let logging = RecordingLogging()
        let storage = try await enrolledStorage()
        let sdk = createTestPushNotificationSdk(storage: storage, logging: logging) { request in
            if request.url?.path.contains("/actions/challenge-1/submit") == true {
                return respondFailure(for: request)
            }
            return respondJson(for: request, body: approveDenyResponseBody())
        }
        let challenge = try await sdk.handleMessage(envelopeMessageData(issuer: issuer, accountId: accountId))
        guard case let .simple(simple) = challenge else {
            Issue.record("expected a simple challenge")
            return
        }

        let result = try await sdk.resolveChallenge(simple.approve())

        #expect(result == .notOk)
        #expect(logging.lines.contains("INFO Resolution not accepted"))
        #expect(logging.lines.contains("DEBUG Challenge 'challenge-1' resolution rejected by the backend (status 400)"))
    }

    @Test func canHandleMessageLogsWhyAMessageIsNotHandled() async throws {
        let logging = RecordingLogging()
        let sdk = createTestPushNotificationSdk(logging: logging) { request in respondSuccess(for: request) }

        _ = try await sdk.canHandleMessage(nil)
        _ = try await sdk.canHandleMessage(envelopeMessageData(issuer: issuer, accountId: accountId, version: "9"))
        _ = try await sdk.canHandleMessage(envelopeMessageData(issuer: issuer, accountId: accountId))

        #expect(logging.lines == [
            "DEBUG Checking whether a message can be handled",
            "DEBUG Message carries no push envelope",
            "DEBUG Checking whether a message can be handled",
            "WARN Push envelope version is not supported by this SDK version",
            "DEBUG Checking whether a message can be handled",
            "DEBUG Message cannot be handled: no enrollment matches it",
        ])
    }

    @Test func eachCallThatLogsNothingElseLogsThatItWasMade() async throws {
        let logging = RecordingLogging()
        let storage = try await enrolledStorage()
        let sdk = createTestPushNotificationSdk(storage: storage, logging: logging) { request in
            if request.url?.path.contains("/actions/") == true {
                return respondJson(for: request, body: approveDenyResponseBody())
            }
            return respondSuccess(for: request)
        }

        _ = try await sdk.hasEnrollment(issuer: issuer, accountId: accountId)
        _ = await sdk.listEnrollments()
        _ = try await sdk.canHandleMessage(envelopeMessageData(issuer: issuer, accountId: accountId))
        let challenge = try await sdk.handleMessage(envelopeMessageData(issuer: issuer, accountId: accountId))
        guard case let .simple(simple) = challenge else {
            Issue.record("expected a simple challenge")
            return
        }
        _ = try await sdk.resolveChallenge(simple.approve())

        #expect(logging.lines.filter { $0.hasPrefix("DEBUG") } == [
            "DEBUG Checking enrollment",
            "DEBUG Listing enrollments",
            "DEBUG Checking whether a message can be handled",
            "DEBUG Handling message",
            "DEBUG Resolving challenge",
        ])
    }

    @Test func anUnreadableEnvelopeIsLoggedWithTheTypeNameOnly() async throws {
        let logging = RecordingLogging()
        let sdk = createTestPushNotificationSdk(logging: logging) { request in respondSuccess(for: request) }

        _ = try await sdk.canHandleMessage([PushEnvelope.key: "not json"])

        let lines = logging.lines.filter { $0.hasPrefix("WARN") }
        let line = try #require(lines.first)
        #expect(lines.count == 1)
        #expect(line.hasPrefix("WARN Push envelope could not be read ("))
        #expect(!line.contains("not json"))
    }

    // --- no Logging ---

    @Test func anOperationCompletesWithoutALogging() async throws {
        let sdk = createTestPushNotificationSdk(logging: nil) { request in respondSuccess(for: request) }

        let enrollment = try await sdk.enrollDevice(
            grant: grant,
            deviceToken: deviceToken,
            deviceTokenType: .fcmToken,
            deviceName: deviceName
        )

        #expect(enrollment.accountId == accountId)
    }

    private func enrolledStorage() async throws -> FakePushNotificationStorage {
        let storage = FakePushNotificationStorage()
        _ = try await storage.createEnrollment(
            issuer: issuer,
            accountId: accountId,
            userName: userName,
            deviceName: deviceName
        )
        return storage
    }

    private func expectNoSecrets(in logging: RecordingLogging) {
        for line in logging.lines {
            for secret in secrets {
                #expect(!line.localizedCaseInsensitiveContains(secret), "'\(secret)' leaked in: \(line)")
            }
        }
    }
}
