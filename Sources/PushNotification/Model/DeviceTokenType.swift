/// What kind of push token the app is supplying to `enrollDevice`/`updateDeviceToken`.
///
/// The app chooses this — the SDK does not infer it from the platform, since more than one is
/// valid on a given platform (e.g. FCM is also usable on iOS).
public enum DeviceTokenType: Sendable {
    case apns
    case fcmToken
    case fcmFid
}
