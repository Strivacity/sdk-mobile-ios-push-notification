import Foundation
@testable import PushNotification
import Testing

/// Exercises `logLabel`.
struct LogLabelTests {
    @Test func anSdkFailureIsLabelledByItsCodeNotItsMessage() {
        let failure = PushNotificationError.networkFailure(message: "secret message", cause: nil)

        #expect(logLabel(failure) == "network_failure")
    }

    @Test func anyOtherFailureIsLabelledByItsFullTypeNameNotItsMessage() {
        let label = logLabel(TestFailure("secret message"))

        #expect(label == String(reflecting: TestFailure.self))
        #expect(!label.contains("secret message"))
    }

    @Test func aURLErrorIsLabelledByItsTypeNameAndCode() {
        let label = logLabel(URLError(.notConnectedToInternet))

        #expect(label.hasSuffix("URLError(-1009)"))
    }
}
