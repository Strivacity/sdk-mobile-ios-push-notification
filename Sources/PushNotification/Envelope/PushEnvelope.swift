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
    static func parse(_ messageData: [String: String]?, logging: Logging? = nil) -> ChallengeEnvelope? {
        guard let raw = messageData?[key] else {
            logging?.debug("Message carries no push envelope")
            return nil
        }

        let envelope: ChallengeEnvelope
        do {
            envelope = try JSONDecoder().decode(ChallengeEnvelope.self, from: Data(raw.utf8))
        } catch {
            logging?.warn("Push envelope could not be read (\(logLabel(error)))")
            return nil
        }

        guard envelope.isUsable else {
            if envelope.version != supportedVersion {
                logging?.warn("Push envelope version is not supported by this SDK version")
            }
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
