import Foundation

/// Encodes `challenge` as an opaque string that `deserializeChallenge(_:)` reads back.
///
/// The string includes the challenge's single-use value. Treat it as a secret: do not log it.
/// Intended for the Flutter plugin; not a supported application API and may change without notice.
@_spi(PluginBridge)
public func serializeChallenge(_ challenge: Challenge) throws -> String {
    let context = challenge.context
    let snapshot = ChallengeSnapshot(
        version: ChallengeSnapshot.currentVersion,
        type: challenge.snapshotType,
        challengeId: context.challengeId,
        challengeValue: context.challengeValue,
        issuer: context.issuer,
        accountId: context.accountId,
        expiresAt: context.expiresAt,
        metadata: context.metadata,
        options: challenge.snapshotOptions
    )

    do {
        let data = try JSONEncoder().encode(snapshot)
        guard let serialized = String(data: data, encoding: .utf8) else {
            throw PushNotificationError.challengeUnavailable(
                message: "The challenge cannot be serialized", status: nil, cause: nil
            )
        }
        return serialized
    } catch let error as PushNotificationError {
        throw error
    } catch {
        throw PushNotificationError.challengeUnavailable(
            message: "The challenge cannot be serialized", status: nil, cause: error
        )
    }
}

/// Rebuilds a challenge from the output of `serializeChallenge(_:)`.
///
/// - Throws: `PushNotificationError.challengeUnavailable` if `serialized` is not a snapshot this
///   SDK version can read.
@_spi(PluginBridge)
public func deserializeChallenge(_ serialized: String) throws -> Challenge {
    guard
        let data = serialized.data(using: .utf8),
        let snapshot = try? JSONDecoder().decode(ChallengeSnapshot.self, from: data),
        let challenge = snapshot.toChallenge() else {
        throw PushNotificationError.challengeUnavailable(
            message: "The serialized challenge cannot be read", status: nil, cause: nil
        )
    }
    return challenge
}

private struct ChallengeSnapshot: Codable {
    static let currentVersion = 1
    static let simple = "simple"
    static let contextMatching = "contextMatching"

    let version: Int
    let type: String
    let challengeId: String
    let challengeValue: String
    let issuer: String
    let accountId: String
    let expiresAt: String
    let metadata: [String: String?]
    let options: [String]?

    /// Returns `nil` if the snapshot's version, fields or type/options combination is unusable.
    func toChallenge() -> Challenge? {
        let requiredFields = [challengeId, challengeValue, issuer, accountId, expiresAt]
        guard version == Self.currentVersion, !requiredFields.contains(where: \.isBlank) else { return nil }

        let context = ChallengeContext(
            challengeId: challengeId,
            challengeValue: challengeValue,
            issuer: issuer,
            accountId: accountId,
            expiresAt: expiresAt,
            metadata: metadata
        )

        switch type {
        case Self.simple:
            return options == nil ? .simple(Challenge.Simple(context: context)) : nil
        case Self.contextMatching:
            guard let options, !options.isEmpty else { return nil }
            return .contextMatching(Challenge.ContextMatching(context: context, options: options))
        default:
            return nil
        }
    }
}

private extension Challenge {
    var snapshotType: String {
        switch self {
        case .simple: ChallengeSnapshot.simple
        case .contextMatching: ChallengeSnapshot.contextMatching
        }
    }

    var snapshotOptions: [String]? {
        switch self {
        case .simple: nil
        case let .contextMatching(challenge): challenge.options
        }
    }
}
