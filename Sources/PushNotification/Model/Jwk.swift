/// A public key in JWK form (RFC 7517).
///
/// `alg` and `kid` are tracked as fields; everything else is an entry in `members`, the key's
/// remaining JWK members (`kty`, `crv`, `x` and `y` for a P-256 key):
///
/// ```
/// Jwk(kid: kid, alg: "ES256", members: ["kty": "EC", "crv": "P-256", "x": x, "y": y])
/// ```
///
/// `members` must hold only the public half; see `Jwk.privateMembers`.
public struct Jwk: Equatable, Sendable {
    public let kid: String
    public let alg: String
    public let members: [String: String]

    public init(kid: String, alg: String, members: [String: String]) {
        self.kid = kid
        self.alg = alg
        self.members = members
    }

    public static let algorithmES256 = "ES256"

    /// The private-key member of an EC key, `d` (RFC 7518 §6.2.2). Must not appear in `members`.
    public static let privateMembers: Set<String> = ["d"]
}

extension Jwk: CustomStringConvertible {
    /// Omits member values.
    public var description: String {
        "Jwk(kid: \(kid), alg: \(alg), members: \(members.keys.sorted()))"
    }
}
