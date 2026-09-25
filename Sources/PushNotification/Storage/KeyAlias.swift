import CryptoKit
import Foundation
import Security

/// The Keychain alias scheme.
///
/// ```
/// sty.base64url(sha256(issuer + 0x00 + accountId)).keyId
/// ```
///
/// `sty` separates the SDK's keys from the host app's own. The hashed segment is per issuer and
/// account. `keyId` is a random per-key id, also used as the JWT `kid`.
enum KeyAlias {
    private static let prefix = "sty"
    private static let separator = "."
    private static let keyIdSize = 16

    /// A fresh, random key id.
    ///
    /// - Throws: `PushNotificationError.storageFailure` if the system can't supply random bytes.
    static func newKeyId() throws -> String {
        var bytes = [UInt8](repeating: 0, count: keyIdSize)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw PushNotificationError.storageFailure(
                message: "A random key id could not be generated",
                cause: NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            )
        }

        return Base64Url.encode(Data(bytes))
    }

    /// Everything up to and including the separator before the key id.
    static func prefixFor(issuer: String, accountId: String) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(issuer.utf8))
        // Delimiter between issuer and accountId.
        hasher.update(data: Data([0]))
        hasher.update(data: Data(accountId.utf8))
        let digest = Data(hasher.finalize())

        return "\(prefix)\(separator)\(Base64Url.encode(digest))\(separator)"
    }

    static func of(issuer: String, accountId: String, keyId: String) -> String {
        prefixFor(issuer: issuer, accountId: accountId) + keyId
    }

    static func keyIdOf(_ alias: String) -> String {
        String(alias.split(separator: Character(separator)).last ?? Substring(alias))
    }

    /// Whether this alias is one of the SDK's, rather than the host app's.
    static func isOurs(_ alias: String) -> Bool {
        alias.hasPrefix("\(prefix)\(separator)")
    }
}
