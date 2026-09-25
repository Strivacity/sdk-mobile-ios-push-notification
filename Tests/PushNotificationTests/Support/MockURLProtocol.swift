import Foundation

/// Intercepts every request made through a `URLSession` built by `mockSession(handler:)`, standing
/// in for the backend in tests.
///
/// Registered per-session, not globally: each `mockSession` call gets its own handler, keyed by a
/// UUID token carried as a request header (`sessionIdHeader`) via
/// `URLSessionConfiguration.httpAdditionalHeaders` — so concurrently-running tests (Swift Testing
/// parallelizes by default) never see each other's handler, even though `MockURLProtocol` itself
/// is one class shared process-wide.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    /// `async`, not just `throws` — a handler that suspends (e.g. awaiting a test-controlled
    /// `Signal`) is a genuine, cancellable suspension point. Backed by a real `Task`, cancelled
    /// from `stopLoading()`, so a test can exercise "the SDK call was cancelled mid-network-call."
    typealias Handler = @Sendable (URLRequest) async throws -> (HTTPURLResponse, Data)

    static let sessionIdHeader = "X-Mock-Session-Id"

    private static let lock = NSLock()
    /// Guarded by `lock`, not by the compiler — the compiler can't see that.
    private nonisolated(unsafe) static var handlers: [String: Handler] = [:]

    static func register(_ handler: @escaping Handler) -> String {
        let token = UUID().uuidString
        lock.lock()
        handlers[token] = handler
        lock.unlock()
        return token
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    private let lock = NSLock()
    private var runningTask: Task<Void, Never>?

    override func startLoading() {
        guard let token = request.value(forHTTPHeaderField: Self.sessionIdHeader) else {
            client?.urlProtocol(self, didFailWithError: TestFailure("request carries no mock session id"))
            return
        }

        Self.lock.lock()
        let handler = Self.handlers[token]
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: TestFailure("no mock handler registered for \(token)"))
            return
        }

        let capturedRequest = request
        let started = Task {
            do {
                let (response, data) = try await handler(capturedRequest)
                guard !Task.isCancelled else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                guard !Task.isCancelled else { return }
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        lock.lock()
        runningTask = started
        lock.unlock()
    }

    override func stopLoading() {
        lock.lock()
        let current = runningTask
        lock.unlock()
        current?.cancel()
    }
}

/// A `URLSession` whose every request is routed to `handler` instead of the network.
func mockSession(handler: @escaping MockURLProtocol.Handler) -> URLSession {
    let token = MockURLProtocol.register(handler)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    configuration.httpAdditionalHeaders = [MockURLProtocol.sessionIdHeader: token]
    return URLSession(configuration: configuration)
}
