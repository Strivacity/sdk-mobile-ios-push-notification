@testable import PushNotification
import Testing

/// Every case carries the code its `.code` mapping sets — a regression guard against a
/// copy-paste mistake wiring the wrong code to a new or existing case. `.code`'s switch is
/// compiler-exhaustive (a missing case fails to build), which rules out a case being silently
/// omitted, but not a case mapped to the *wrong* code — this still catches that.
struct PushNotificationErrorCodesTests {
    @Test func everyCaseCarriesItsDocumentedErrorCode() {
        let casesToCodes: [(PushNotificationError, String)] = [
            (.invalidIssuer(issuer: "https://issuer.example.com"), "invalid_issuer"),
            (.invalidDeviceName, "invalid_device_name"),
            (.invalidGrant(message: "message"), "invalid_grant"),
            (.enrollmentRejected(message: "message", status: nil, cause: nil), "enrollment_rejected"),
            (.alreadyEnrolled(issuer: "https://issuer.example.com", accountId: "account-1"), "already_enrolled"),
            (.unenrollmentRejected(message: "message", status: nil, cause: nil), "unenrollment_rejected"),
            (.tokenUpdateRejected(message: "message", status: nil, cause: nil), "token_update_rejected"),
            (.notEnrolled(accountId: "account-1"), "not_enrolled"),
            (.challengeUnavailable(message: "message", status: nil, cause: nil), "challenge_unavailable"),
            (.unsupportedChallengeType(challengeType: "aType"), "unsupported_challenge_type"),
            (.unsupportedAlgorithm(algorithm: "RS256", accepted: ["ES256"]), "unsupported_algorithm"),
            (.softwareBackedKey, "software_backed_key"),
            (.storageFailure(message: "message", cause: nil), "storage_failure"),
            (.networkFailure(message: "message", cause: nil), "network_failure"),
            (.invalidChallengeOption(challengeId: "challenge-1"), "invalid_challenge_option"),
        ]

        for (error, expectedCode) in casesToCodes {
            #expect(error.code == expectedCode, "\(error) should carry \(expectedCode)")
        }
    }
}
