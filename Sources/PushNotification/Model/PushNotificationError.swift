import Foundation

/// Everything this SDK throws.
///
/// Error messages reach release-build error reporting. Do not include one-time tokens, JWTs, key
/// material, challenge metadata, or anything identifying a user. Issuer URLs, key ids, challenge
/// ids, and HTTP status codes are safe to include.
public enum PushNotificationError: Error {
    /// The issuer is not an absolute `https` URL.
    case invalidIssuer(issuer: String)

    /// The device name doesn't satisfy the SDK's constraints: 1-64 characters after trimming,
    /// with no other restriction. The offending value is deliberately not included.
    case invalidDeviceName

    /// The enrollment grant could not be read: a parameter is missing, or the URL is malformed.
    case invalidGrant(message: String)

    /// Enrollment was refused. Not retryable; obtain a fresh grant.
    case enrollmentRejected(message: String, status: Int?, cause: Error?)

    /// This device already holds an enrollment for this issuer and account. Un-enroll first to
    /// replace it.
    case alreadyEnrolled(issuer: String, accountId: String)

    /// Un-enrollment was refused. The local enrollment is removed regardless.
    case unenrollmentRejected(message: String, status: Int?, cause: Error?)

    /// The backend refused a device token update.
    case tokenUpdateRejected(message: String, status: Int?, cause: Error?)

    /// No enrollment is held for the account in question.
    case notEnrolled(accountId: String)

    /// No usable challenge: none in the payload, or the backend refused it, returned one this SDK
    /// can't read, or failed its resolution.
    case challengeUnavailable(message: String, status: Int?, cause: Error?)

    /// The backend described a challenge type this version of the SDK does not implement.
    case unsupportedChallengeType(challengeType: String)

    /// A storage implementation produced a key whose algorithm is not on the accepted list.
    case unsupportedAlgorithm(algorithm: String, accepted: Set<String>)

    /// The key could only be created in software, and software-backed keys are not allowed. Pass
    /// `allowSoftwareBackedKeys = true` to accept one.
    case softwareBackedKey

    /// Key generation, lookup, or signing failed, or an enrollment could not be recorded or
    /// removed.
    case storageFailure(message: String, cause: Error?)

    /// The backend could not be reached, or the response was unreadable.
    case networkFailure(message: String, cause: Error?)

    /// `Challenge.ContextMatching.select(_:)` was called with an option not among those the
    /// challenge offered.
    case invalidChallengeOption(challengeId: ChallengeId)

    /// A stable, greppable identifier for the failure.
    public var code: String {
        switch self {
        case .invalidIssuer: "invalid_issuer"
        case .invalidDeviceName: "invalid_device_name"
        case .invalidGrant: "invalid_grant"
        case .enrollmentRejected: "enrollment_rejected"
        case .alreadyEnrolled: "already_enrolled"
        case .unenrollmentRejected: "unenrollment_rejected"
        case .tokenUpdateRejected: "token_update_rejected"
        case .notEnrolled: "not_enrolled"
        case .challengeUnavailable: "challenge_unavailable"
        case .unsupportedChallengeType: "unsupported_challenge_type"
        case .unsupportedAlgorithm: "unsupported_algorithm"
        case .softwareBackedKey: "software_backed_key"
        case .storageFailure: "storage_failure"
        case .networkFailure: "network_failure"
        case .invalidChallengeOption: "invalid_challenge_option"
        }
    }

    public var message: String {
        switch self {
        case let .invalidIssuer(issuer):
            "Issuer '\(issuer)' is not an absolute https URL"
        case .invalidDeviceName:
            "Device name must be 1-64 characters"
        case let .invalidGrant(message):
            message
        case let .enrollmentRejected(message, _, _):
            message
        case let .alreadyEnrolled(issuer, accountId):
            "Account '\(accountId)' is already enrolled on this device for issuer '\(issuer)'"
        case let .unenrollmentRejected(message, _, _):
            message
        case let .tokenUpdateRejected(message, _, _):
            message
        case let .notEnrolled(accountId):
            "No enrollment is held for account '\(accountId)'"
        case let .challengeUnavailable(message, _, _):
            message
        case let .unsupportedChallengeType(challengeType):
            "Backend offered challenge type '\(challengeType)', which this SDK version cannot present"
        case let .unsupportedAlgorithm(algorithm, accepted):
            "Storage produced a '\(algorithm)' key; accepted algorithms are \(accepted.joined(separator: ", "))"
        case .softwareBackedKey:
            "The key could only be created in software. Set allowSoftwareBackedKeys = true to accept that"
        case let .storageFailure(message, _):
            message
        case let .networkFailure(message, _):
            message
        case let .invalidChallengeOption(challengeId):
            "The selected option was not among those offered for challenge '\(challengeId)'"
        }
    }

    /// The HTTP status the backend responded with, where applicable.
    public var status: Int? {
        switch self {
        case let .enrollmentRejected(_, status, _),
             let .unenrollmentRejected(_, status, _),
             let .tokenUpdateRejected(_, status, _),
             let .challengeUnavailable(_, status, _):
            status
        default:
            nil
        }
    }

    /// The underlying failure, where this error wraps one.
    public var cause: Error? {
        switch self {
        case let .enrollmentRejected(_, _, cause),
             let .unenrollmentRejected(_, _, cause),
             let .tokenUpdateRejected(_, _, cause),
             let .challengeUnavailable(_, _, cause),
             let .storageFailure(_, cause),
             let .networkFailure(_, cause):
            cause
        default:
            nil
        }
    }
}

extension PushNotificationError: LocalizedError {
    public var errorDescription: String? {
        message
    }
}
