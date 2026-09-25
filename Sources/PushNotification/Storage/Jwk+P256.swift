import Foundation

extension Jwk {
    /// Builds the JWK for a P-256 public key.
    ///
    /// - Parameter x963Representation: the uncompressed point form CryptoKit hands back
    ///   (`0x04 || X(32) || Y(32)`, 65 bytes) — what both `P256.Signing.PublicKey` and
    ///   `SecureEnclave.P256.Signing.PublicKey` expose.
    init(p256PublicKey x963Representation: Data, kid: String) {
        precondition(
            x963Representation.count == 65 && x963Representation.first == 0x04,
            "Expected an uncompressed P-256 point"
        )

        let coordinates = x963Representation.dropFirst()
        let xCoordinate = coordinates.prefix(32)
        let yCoordinate = coordinates.suffix(32)

        self.init(
            kid: kid,
            alg: Jwk.algorithmES256,
            members: [
                "kty": "EC",
                "crv": "P-256",
                "x": Base64Url.encode(Data(xCoordinate)),
                "y": Base64Url.encode(Data(yCoordinate)),
            ]
        )
    }
}
