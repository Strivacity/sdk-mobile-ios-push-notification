@testable import PushNotification
import Testing

/// Exercises `EnrollmentGrant`'s own logic directly. `EnrollmentGrant.parse` is covered separately
/// in `EnrollmentGrantParseTests`.
struct EnrollmentGrantTests {
    @Test func descriptionDoesNotContainTheOneTimeToken() {
        let grant = EnrollmentGrant(
            issuer: "https://issuer.example.com",
            oneTimeToken: "super-secret-ott",
            accountId: "account-1",
            displayUserName: "Jane"
        )

        #expect(!grant.description.contains("super-secret-ott"))
    }
}
