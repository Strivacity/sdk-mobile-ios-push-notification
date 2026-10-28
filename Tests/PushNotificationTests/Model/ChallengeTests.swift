@testable import PushNotification
import Testing

/// Exercises `Challenge`/`ChallengeResolution` directly — an isolated unit test rather than one
/// through `PushNotificationInterface`: both types are constructible from within the module (via
/// `@testable import`) and need no fakes/mocks to exercise meaningfully.
struct ChallengeTests {
    let context = ChallengeContext(
        challengeId: "challenge-1",
        challengeValue: "challenge-value",
        issuer: "https://issuer.example.com",
        accountId: "account-1",
        expiresAt: "2026-10-01T14:30:00Z",
        metadata: ["place": "New York"]
    )

    @Test func denyCarriesTheChallengesFieldsThroughToTheResolutionWithActionDeny() {
        let resolution = Challenge.simple(Challenge.Simple(context: context)).deny()

        #expect(resolution.challengeId == context.challengeId)
        #expect(resolution.challengeValue == context.challengeValue)
        #expect(resolution.issuer == context.issuer)
        #expect(resolution.accountId == context.accountId)
        #expect(resolution.action == "deny")
    }

    @Test func approveCarriesTheChallengesFieldsThroughToTheResolutionWithActionApprove() {
        let resolution = Challenge.Simple(context: context).approve()

        #expect(resolution.challengeId == context.challengeId)
        #expect(resolution.challengeValue == context.challengeValue)
        #expect(resolution.action == "approve")
    }

    @Test func selectWithAnOfferedOptionCarriesTheChallengesFieldsThroughWithTheOptionAsTheAction() throws {
        let challenge = Challenge.ContextMatching(context: context, options: ["12", "26", "84"])

        let resolution = try challenge.select("26")

        #expect(resolution.challengeId == context.challengeId)
        #expect(resolution.challengeValue == context.challengeValue)
        #expect(resolution.action == "26")
    }

    @Test func selectWithAnOptionThatWasNotOfferedThrowsInvalidChallengeOption() throws {
        let challenge = Challenge.ContextMatching(context: context, options: ["12", "26", "84"])

        let failure = try #require(throws: PushNotificationError.self) {
            try challenge.select("99")
        }

        guard case let .invalidChallengeOption(challengeId) = failure else {
            Issue.record("expected .invalidChallengeOption, got \(failure)")
            return
        }
        #expect(challengeId == context.challengeId)
    }

    @Test func challengeDescriptionDoesNotContainTheChallengeValueOrMetadata() {
        let text = Challenge.simple(Challenge.Simple(context: context)).description

        #expect(!text.contains(context.challengeValue))
        #expect(!text.contains("New York"))
    }

    @Test func challengeResolutionDescriptionDoesNotContainTheChallengeValue() {
        let text = Challenge.simple(Challenge.Simple(context: context)).deny().description

        #expect(!text.contains(context.challengeValue))
    }
}
