/// The relationship between one account, this device, and one keypair.
///
/// Carries nothing secret.
public struct Enrollment: Equatable, Sendable {
    public let issuer: String
    public let accountId: String
    public let keyId: String
    public let userName: String?
    public let deviceName: String?

    public init(issuer: String, accountId: String, keyId: String, userName: String?, deviceName: String?) {
        self.issuer = issuer
        self.accountId = accountId
        self.keyId = keyId
        self.userName = userName
        self.deviceName = deviceName
    }
}
