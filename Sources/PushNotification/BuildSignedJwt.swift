import Foundation

/// Assembles a compact JWT: header, payload, and signature, base64url-encoded and dot-separated.
///
/// - Parameter sign: signs the header-and-payload signing input and returns the signature as a
///   base64url string.
func buildSignedJwt(
    keyId: String,
    algorithm: String,
    payload: String,
    sign: (_ signingInput: String) async throws -> String
) async throws -> String {
    let headerData = try JSONEncoder().encode(JwtHeader(alg: algorithm, kid: keyId))
    guard let header = String(bytes: headerData, encoding: .utf8) else {
        throw PushNotificationError.storageFailure(message: "JWT header could not be encoded", cause: nil)
    }

    let signingInput = "\(Base64Url.encode(header)).\(Base64Url.encode(payload))"
    let signature = try await sign(signingInput)
    return "\(signingInput).\(signature)"
}

/// Field order matches declaration order under `JSONEncoder` — not load-bearing for a JWT
/// consumer (JOSE doesn't mandate header key order), just a readability nicety.
private struct JwtHeader: Encodable {
    let alg: String
    let kid: String
    let typ = "JWT"
}
