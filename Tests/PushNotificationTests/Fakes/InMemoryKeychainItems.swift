import Foundation
@testable import PushNotification

/// In-memory `KeychainItems` fake. Each operation can be made to throw.
final class InMemoryKeychainItems: KeychainItems, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private var failing: Set<Operation> = []

    enum Operation {
        case add, read, delete
    }

    /// Makes every later call of `operation` throw.
    func fail(_ operation: Operation) {
        withLock { failing.insert(operation) }
    }

    /// Stores `data` under `account` as-is, bypassing any failure set up with `fail`.
    func store(_ data: Data, account: String) {
        withLock { items[account] = data }
    }

    var accounts: Set<String> {
        withLock { Set(items.keys) }
    }

    func add(_ data: Data, account: String) throws {
        try withLock {
            try check(.add)
            items[account] = data
        }
    }

    func data(account: String) throws -> Data? {
        try withLock {
            try check(.read)
            return items[account]
        }
    }

    func all() throws -> [String: Data] {
        try withLock {
            try check(.read)
            return items
        }
    }

    func delete(account: String) throws {
        try withLock {
            try check(.delete)
            items[account] = nil
        }
    }

    private func check(_ operation: Operation) throws {
        if failing.contains(operation) {
            throw TestFailure("simulated Keychain \(operation) failure")
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
