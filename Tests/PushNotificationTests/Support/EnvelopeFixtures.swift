@testable import PushNotification

let farFutureExpiresAt = "9999-12-31T23:59:59Z"
private let realisticMetadataJson = #"{"loginTimestamp":"1700000000"}"#

/// Builds a syntactically valid push envelope payload as a single-entry dictionary, for
/// `canHandleMessage`/`handleMessage` tests.
func envelopeMessageData(
    issuer: String,
    accountId: String,
    challengeId: String = "challenge-1",
    challenge: String = "challenge-value",
    version: String = "1"
) -> [String: String] {
    let envelopeJson = """
    {"version":"\(version)","challengeId":"\(challengeId)","challenge":"\(challenge)",\
    "accountId":"\(accountId)","issuer":"\(issuer)"}
    """
    return [PushEnvelope.key: envelopeJson]
}

/// A `ChallengeResponse` JSON body with `action.type = "simple"`.
func approveDenyResponseBody(
    expireAt: String = farFutureExpiresAt,
    metadataJson: String = realisticMetadataJson
) -> String {
    """
    {"expireAt":"\(expireAt)","metadata":\(metadataJson),"action":{"type":"\(ActionTypes.simple)"}}
    """
}

/// A `ChallengeResponse` JSON body with `action.type = "contextMatching"` and the given options.
func contextMatchingResponseBody(options: [String], expireAt: String = farFutureExpiresAt) -> String {
    let optionsJson = options.map { "\"\($0)\"" }.joined(separator: ",")
    return """
    {"expireAt":"\(expireAt)","metadata":\(realisticMetadataJson),\
    "action":{"type":"\(ActionTypes.contextMatching)","options":[\(optionsJson)]}}
    """
}

/// A `ChallengeResponse` body with an unrecognized `action.type`.
func unsupportedChallengeResponseBody(expireAt: String = farFutureExpiresAt) -> String {
    """
    {"expireAt":"\(expireAt)","metadata":\(realisticMetadataJson),"action":{"type":"aFutureChallengeType"}}
    """
}
