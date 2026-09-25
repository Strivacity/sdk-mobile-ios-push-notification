/// Identifies one challenge. Safe to log.
public typealias ChallengeId = String

/// Fields shared by every `Challenge` variant.
struct ChallengeContext: Equatable {
    let challengeId: ChallengeId
    /// A single-use value that must be presented, signed, when the challenge is resolved. Not
    /// exposed to the host app; absent from `description` and error messages.
    let challengeValue: String
    let issuer: String
    let accountId: String
    let expiresAt: String
    let metadata: [String: String?]

    func resolution(action: String) -> ChallengeResolution {
        ChallengeResolution(
            challengeId: challengeId,
            challengeValue: challengeValue,
            issuer: issuer,
            accountId: accountId,
            action: action
        )
    }
}

/// An MFA request waiting on a decision.
///
/// Cases cannot be constructed outside the SDK — `Simple` and `ContextMatching` carry an
/// internal `ChallengeContext`, so a `Challenge` can only be obtained from the SDK.
public enum Challenge: Sendable {
    /// Nested so its name doesn't collide with the wire `Action` type in `Net/Wire.swift` — plain
    /// top-level `private` in Swift scopes *visibility* to the file, not the declaration's
    /// identity, so two top-level types can't share a name even if both are private.
    private enum ActionValue {
        static let approve = "approve"
        static let deny = "deny"
    }

    /// "Allow this sign-in?" — nothing to choose between.
    case simple(Simple)

    /// The user picks one of `options`, shown to them alongside the same value on the device
    /// signing in. The backend judges the answer.
    case contextMatching(ContextMatching)

    public struct Simple: Sendable {
        let context: ChallengeContext

        public func approve() -> ChallengeResolution {
            context.resolution(action: ActionValue.approve)
        }
    }

    public struct ContextMatching: Sendable {
        let context: ChallengeContext
        public let options: [String]

        /// - Throws: `PushNotificationError.invalidChallengeOption` if `option` is not one of
        ///   `options`.
        public func select(_ option: String) throws -> ChallengeResolution {
            guard options.contains(option) else {
                throw PushNotificationError.invalidChallengeOption(challengeId: context.challengeId)
            }
            return context.resolution(action: option)
        }
    }

    var context: ChallengeContext {
        switch self {
        case let .simple(challenge): challenge.context
        case let .contextMatching(challenge): challenge.context
        }
    }

    public var challengeId: ChallengeId {
        context.challengeId
    }

    /// Which backend this challenge came from. A device may hold enrollments against several.
    public var issuer: String {
        context.issuer
    }

    public var accountId: String {
        context.accountId
    }

    /// When this challenge expires: an ISO 8601 / RFC 3339 instant string (e.g.
    /// `2026-10-01T14:30:00Z`). The SDK enforces nothing; the backend does.
    public var expiresAt: String {
        context.expiresAt
    }

    /// Backend-supplied context for the decision (e.g. device, location, time).
    ///
    /// Keys are not guaranteed and values may be `nil`; ignore entries this version does not
    /// recognise.
    public var metadata: [String: String?] {
        context.metadata
    }

    /// The user refused. A recorded refusal is a successful resolution, not an error.
    public func deny() -> ChallengeResolution {
        context.resolution(action: ActionValue.deny)
    }
}

extension Challenge: CustomStringConvertible {
    /// Omits the challenge value and `metadata`.
    public var description: String {
        let kind =
            switch self {
            case .simple: "Simple"
            case .contextMatching: "ContextMatching"
            }
        return "Challenge.\(kind)(challengeId: \(challengeId), issuer: \(issuer), " +
            "accountId: \(accountId), expiresAt: \(expiresAt))"
    }
}

/// A user's answer, ready to submit. Obtained from a `Challenge` and opaque to the app.
public struct ChallengeResolution: Sendable {
    let challengeId: ChallengeId
    let challengeValue: String
    let issuer: String
    let accountId: String
    /// An offered option, or a refusal.
    let action: String
}

extension ChallengeResolution: CustomStringConvertible {
    public var description: String {
        "ChallengeResolution(challengeId: \(challengeId), action: \(action))"
    }
}

/// The outcome of a resolution. Detail beyond this lives in the backend's own logs.
public enum ResolutionResult: Sendable {
    case ok
    case notOk
}
