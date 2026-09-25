import Foundation

private let schemeHTTPS = "https"

/// Reduces an issuer to `https://authority` (scheme and lowercased authority).
///
/// - Throws: `PushNotificationError.invalidIssuer` if the value is not an absolute `https` URL.
func normalizeIssuer(_ issuer: String) throws -> String {
    let trimmed = issuer.trimmingCharacters(in: .whitespacesAndNewlines)

    guard
        let components = URLComponents(string: trimmed),
        let scheme = components.scheme, scheme.lowercased() == schemeHTTPS,
        let host = components.host, !host.isEmpty,
        components.user == nil, components.password == nil else {
        throw PushNotificationError.invalidIssuer(issuer: issuer)
    }

    let port = components.port.map { ":\($0)" } ?? ""

    return "\(schemeHTTPS)://\((host + port).lowercased())"
}
