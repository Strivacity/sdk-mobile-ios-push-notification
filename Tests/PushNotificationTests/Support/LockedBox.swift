import Foundation

/// A small `Sendable` mutable box for capturing one value (typically the outgoing `URLRequest`)
/// across a mock handler's closure boundary in a test — Swift's strict concurrency checking
/// doesn't allow closing over a plain `var` across a `@Sendable` closure without something like
/// this.
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?

    var value: T? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            stored = newValue
        }
    }
}
