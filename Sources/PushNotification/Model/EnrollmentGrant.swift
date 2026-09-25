import Foundation

/// The payload authorizing this device to enroll, delivered out of band as a URL — scanned from a
/// QR code, or arriving as a deep link.
public struct EnrollmentGrant: Equatable, Sendable {
    /// Normalized: scheme plus lowercased authority.
    public let issuer: String
    public let oneTimeToken: String
    public let accountId: String
    public let displayUserName: String

    public init(issuer: String, oneTimeToken: String, accountId: String, displayUserName: String) {
        self.issuer = issuer
        self.oneTimeToken = oneTimeToken
        self.accountId = accountId
        self.displayUserName = displayUserName
    }

    /// Wire name for `EnrollmentGrant.issuer`.
    private static let paramIssuer = "issuer"
    private static let paramOneTimeToken = "one_time_token"
    private static let paramAccountId = "account_id"
    private static let paramUserName = "username"

    /// Reads a grant from a scanned or deep-linked `URL`. Converting a scanned string or universal
    /// link to a `URL` is the app's responsibility.
    ///
    /// Unknown query parameters are ignored.
    ///
    /// - Throws: `PushNotificationError.invalidGrant` if a required parameter is missing, or the
    ///   `URL` has no query. The message never includes parameter values.
    ///   `PushNotificationError.invalidIssuer` if the issuer parameter isn't an absolute `https`
    ///   URL.
    public static func parse(_ url: URL) throws -> EnrollmentGrant {
        guard
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            !queryItems.isEmpty else {
            throw PushNotificationError.invalidGrant(message: "Enrollment grant has no readable query parameters")
        }

        func value(for name: String) -> String? {
            queryItems.last { $0.name == name }?.value.flatMap { $0.isBlank ? nil : $0 }
        }

        func required(_ name: String) throws -> String {
            guard let value = value(for: name) else {
                throw PushNotificationError.invalidGrant(message: "Enrollment grant is missing the '\(name)' parameter")
            }
            return value
        }

        return try EnrollmentGrant(
            issuer: normalizeIssuer(required(paramIssuer)),
            oneTimeToken: required(paramOneTimeToken),
            accountId: required(paramAccountId),
            displayUserName: required(paramUserName)
        )
    }
}

extension EnrollmentGrant: CustomStringConvertible {
    /// Omits `oneTimeToken`.
    public var description: String {
        "EnrollmentGrant(issuer: \(issuer), accountId: \(accountId), displayUserName: \(displayUserName))"
    }
}
