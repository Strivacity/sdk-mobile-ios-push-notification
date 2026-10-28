import Foundation

// These mirror the backend's request and response shapes and are kept separate from the domain
// model. Resolution, un-enrollment, and token-update requests are a raw signed JWT string, sent
// as `application/jwt`, so they need no wire type here.
//
// Naming: a request body is `...Request`, a response body `...Response`; an embedded value
// carries no suffix.

extension Jwk {
    /// Builds the wire JWK object from `members`, `alg`, and `kid`.
    var wireObject: [String: String] {
        var object = members
        object["alg"] = alg
        object["kid"] = kid
        return object
    }
}

/// The one-time token travels as an `Authorization: Bearer <token>` header, not in this body.
/// No `accountId` either — the one-time token uniquely identifies the account backend-side.
struct EnrollRequest: Encodable {
    /// `ios`.
    let platform: String
    /// `apns`, `fcmToken`, or `fcmFid`.
    let deviceTokenType: String
    let deviceToken: String
    let deviceName: String
    /// Public key as a JWK object.
    let publicKey: [String: String]
}

/// A challenge's detail.
struct ChallengeResponse: Decodable {
    /// ISO 8601 / RFC 3339 instant string (e.g. `2026-10-01T14:30:00Z`).
    let expireAt: String
    /// Backend-supplied context. Values are mixed JSON types; flattened to strings during mapping.
    let metadata: [String: JSONValue]
    let action: Action

    private enum CodingKeys: String, CodingKey {
        case expireAt, metadata, action
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expireAt = try container.decode(String.self, forKey: .expireAt)
        metadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .metadata) ?? [:]
        action = try container.decode(Action.self, forKey: .action)
    }
}

/// `type` selects the challenge variant. `options` lists acceptable answers for context matching;
/// empty for approve/deny.
struct Action: Decodable {
    let type: String
    let options: [String]

    private enum CodingKeys: String, CodingKey {
        case type, options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        options = try container.decodeIfPresent([String].self, forKey: .options) ?? []
    }
}

/// Action type identifiers, fixed by the backend contract.
enum ActionTypes {
    static let simple = "simple"
    static let contextMatching = "contextMatching"
}

/// Action values accepted for approve/deny. Context matching also accepts `deny`, or one of the
/// offered options.
enum Actions {
    static let approve = "approve"
    static let deny = "deny"
}

enum Platforms {
    static let ios = "ios"
}

extension DeviceTokenType {
    /// Wire value for a `DeviceTokenType`.
    var wireValue: String {
        switch self {
        case .apns: "apns"
        case .fcmToken: "fcmToken"
        case .fcmFid: "fcmFid"
        }
    }
}
