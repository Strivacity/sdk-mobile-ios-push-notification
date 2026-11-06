import os

/// Receives the SDK's log messages.
///
/// Implementations must be thread-safe, and must not crash or block.
public protocol Logging: Sendable {
    func debug(_ body: String)
    func info(_ body: String)
    func warn(_ body: String)
    func error(_ body: String)
}

/// Logs to the unified logging system.
public struct DefaultLogging: Logging {
    private let logger = Logger(subsystem: "com.strivacity.PushNotification", category: "PushNotification")

    public init() {}

    public func debug(_ body: String) {
        logger.debug("\(body, privacy: .public)")
    }

    public func info(_ body: String) {
        logger.info("\(body, privacy: .public)")
    }

    public func warn(_ body: String) {
        logger.warning("\(body, privacy: .public)")
    }

    public func error(_ body: String) {
        logger.error("\(body, privacy: .public)")
    }
}
