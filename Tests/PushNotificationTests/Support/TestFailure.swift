/// A plain error for test fakes and mocks to throw, carrying a message for failure output.
struct TestFailure: Error, CustomStringConvertible, Sendable {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
