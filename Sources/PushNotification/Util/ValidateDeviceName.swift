import Foundation

/// Validates that the trimmed device name is 1-64 characters long, with no other restriction.
///
/// - Throws: `PushNotificationError.invalidDeviceName` if the trimmed `deviceName` is empty or
///   exceeds 64 characters. The check applies to the trimmed value; the original, untrimmed
///   string is what the SDK sends to the backend and stores.
func validateDeviceName(_ deviceName: String) throws {
    let length = deviceName.trimmingCharacters(in: .whitespacesAndNewlines).count
    guard (1 ... 64).contains(length) else {
        throw PushNotificationError.invalidDeviceName
    }
}
