import Foundation

/// The failure's SDK error code, else its full type name (with the code, for a `URLError`).
/// Never its message.
func logLabel(_ failure: Error) -> String {
    if let error = failure as? PushNotificationError {
        return error.code
    }
    // Held as an `Error`, a `URLError` reports its type as `NSError`.
    if let urlError = failure as? URLError {
        return "\(String(reflecting: URLError.self))(\(urlError.code.rawValue))"
    }
    return String(reflecting: type(of: failure))
}
