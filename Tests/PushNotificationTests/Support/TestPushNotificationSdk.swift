import Foundation
@testable import PushNotification

/// Builds a `PushNotification` wired to the given storage, with a mocked `URLSession` standing in
/// for the backend.
///
/// Takes the `PushNotificationStorage` protocol, not the concrete fake actor, so a test can pass a
/// small delegating wrapper around a fake to make one specific operation throw or return bad data.
func createTestPushNotificationSdk(
    storage: PushNotificationStorage = FakePushNotificationStorage(),
    handleRequest: @escaping MockURLProtocol.Handler
) -> PushNotification {
    let client = PushNotificationClient(session: mockSession(handler: handleRequest))
    return PushNotification(storage: storage, client: client)
}

/// A generic 2xx response, for a test that doesn't care about the response body.
func respondSuccess(for request: URLRequest) -> (HTTPURLResponse, Data) {
    (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
}

/// A generic non-2xx response, for a test exercising the backend-refusal path.
func respondFailure(for request: URLRequest, status: Int = 400) -> (HTTPURLResponse, Data) {
    let headers = ["Content-Type": "application/json"]
    return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, Data())
}

/// A 200 response carrying a JSON body, for a test asserting on the deserialized result.
func respondJson(for request: URLRequest, body: String) -> (HTTPURLResponse, Data) {
    let headers = ["Content-Type": "application/json"]
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
    return (response, Data(body.utf8))
}

/// For a test where the call under test should never reach the backend at all.
func failIfCalled(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
    throw TestFailure("no backend call was expected, but one was made to \(request.url?.absoluteString ?? "?")")
}
