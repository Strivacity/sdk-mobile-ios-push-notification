import Foundation

/// Base64url without padding (RFC 7515, appendix C).
enum Base64Url {
    static func encode(_ bytes: Data) -> String {
        bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func encode(_ text: String) -> String {
        encode(Data(text.utf8))
    }

    static func decode(_ text: String) -> Data? {
        var base64 =
            text
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")

        let paddingLength = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: paddingLength))

        return Data(base64Encoded: base64)
    }
}
