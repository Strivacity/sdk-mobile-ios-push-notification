@testable import PushNotification

/// The order in which storage operations were called.
actor CallLog {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}

/// Delegates to another `PushNotificationStorage`, recording each call that changes what is stored.
struct RecordingStorage: PushNotificationStorage {
    let delegate: PushNotificationStorage
    let log: CallLog

    func getPublicKey(issuer: String, accountId: String) async throws -> Jwk? {
        try await delegate.getPublicKey(issuer: issuer, accountId: accountId)
    }

    func createSignature(issuer: String, accountId: String, keyId: String, data: String) async throws -> String {
        try await delegate.createSignature(issuer: issuer, accountId: accountId, keyId: keyId, data: data)
    }

    func createEnrollment(issuer: String, accountId: String, userName: String?,
                          deviceName: String?) async throws -> Jwk {
        await log.record("createEnrollment")
        return try await delegate.createEnrollment(
            issuer: issuer,
            accountId: accountId,
            userName: userName,
            deviceName: deviceName
        )
    }

    func listEnrollments() async -> [Enrollment] {
        await delegate.listEnrollments()
    }

    func removeEnrollment(issuer: String, accountId: String) async throws {
        await log.record("removeEnrollment")
        try await delegate.removeEnrollment(issuer: issuer, accountId: accountId)
    }
}
