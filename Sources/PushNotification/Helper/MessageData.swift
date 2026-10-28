import Foundation

/// Helpers for reading the SDK's push envelope out of a delivered notification payload.
public enum MessageData {
    /// The push envelope from a notification's `userInfo`, as the `[String: String]`
    /// `PushNotificationInterface.canHandleMessage`/`handleMessage` expect.
    ///
    /// For a payload read from `UNNotification.request.content.userInfo` (or
    /// `UNNotificationResponse.notification.request.content.userInfo`) after the user taps an
    /// alert notification — the app is foregrounded and processes the challenge then. The SDK
    /// requires no Notification Service Extension.
    ///
    /// - Returns: `nil` if `userInfo` holds no entry for the SDK's envelope key.
    public static func from(userInfo: [AnyHashable: Any]) -> [String: String]? {
        guard let envelope = userInfo[PushEnvelope.key] as? String else { return nil }
        return [PushEnvelope.key: envelope]
    }
}
