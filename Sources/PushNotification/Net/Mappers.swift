/// Maps backend responses to domain types.
///
/// `toDomain` combines the fetched `ChallengeResponse` with the push `ChallengeEnvelope`: the
/// response describes what is being asked; the envelope supplies the challenge id and value.
extension ChallengeResponse {
    func toDomain(envelope: ChallengeEnvelope, normalizedIssuer: String) throws -> Challenge {
        try checkMetadataNotEmpty()

        let flattenedMetadata = metadata.flattenedToMetadata()

        let context = ChallengeContext(
            challengeId: envelope.challengeId,
            challengeValue: envelope.challenge,
            issuer: normalizedIssuer,
            accountId: envelope.accountId,
            expiresAt: expireAt,
            metadata: flattenedMetadata
        )

        switch action.type {
        case ActionTypes.simple:
            return .simple(Challenge.Simple(context: context))
        case ActionTypes.contextMatching:
            // The backend contract guarantees at least one option for a context-matching
            // challenge — a `select` that could never succeed is a contract violation, not a
            // shape the SDK should hand the App.
            guard !action.options.isEmpty else {
                throw PushNotificationError.challengeUnavailable(
                    message: "Context-matching challenge arrived with no options, contrary to the backend contract",
                    status: nil,
                    cause: nil
                )
            }
            return .contextMatching(Challenge.ContextMatching(context: context, options: action.options))
        default:
            throw PushNotificationError.unsupportedChallengeType(challengeType: action.type)
        }
    }
}

/// The backend contract guarantees metadata is never empty — a timestamp is always present, at
/// minimum.
private extension ChallengeResponse {
    func checkMetadataNotEmpty() throws {
        guard !metadata.isEmpty else {
            throw PushNotificationError.challengeUnavailable(
                message: "Challenge metadata was empty, contrary to the backend contract",
                status: nil,
                cause: nil
            )
        }
    }
}
