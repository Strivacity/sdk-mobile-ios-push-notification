import Foundation

/// The push payload's envelope.
///
/// `challengeId` identifies the challenge and is used to fetch its detail. `challenge` is a
/// single-use value that must accompany `challengeId` when the challenge is resolved; it does not
/// appear in the fetched detail.
struct ChallengeEnvelope: Decodable, Equatable {
    let version: String
    let challengeId: String
    let challenge: String
    let accountId: String
    let issuer: String
}

/// Reads the envelope out of a platform message payload.
enum PushEnvelope {
    /// The envelope's key in the message payload.
    static let key = "com.strivacity"

    /// The only envelope version this SDK implements.
    static let supportedVersion = "1"

    /// Returns `nil` if no envelope is present, it cannot be parsed, or its version is not
    /// `supportedVersion`.
    static func parse(_ messageData: [String: String]?) -> ChallengeEnvelope? {
        guard let raw = messageData?[key], let data = raw.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ChallengeEnvelope.self, from: data),
              envelope.isUsable else {
            return nil
        }

        return envelope
    }
}

private extension ChallengeEnvelope {
    var isUsable: Bool {
        version == PushEnvelope.supportedVersion &&
            !challengeId.isBlank &&
            !challenge.isBlank &&
            !accountId.isBlank &&
            !issuer.isBlank
    }
}
