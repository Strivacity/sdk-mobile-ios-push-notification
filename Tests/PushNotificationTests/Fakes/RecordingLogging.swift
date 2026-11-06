import Foundation
@testable import PushNotification

/// A `Logging` that records each line, prefixed with its level.
final class RecordingLogging: Logging, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func debug(_ body: String) {
        record("DEBUG \(body)")
    }

    func info(_ body: String) {
        record("INFO \(body)")
    }

    func warn(_ body: String) {
        record("WARN \(body)")
    }

    func error(_ body: String) {
        record("ERROR \(body)")
    }

    private func record(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(line)
    }
}
