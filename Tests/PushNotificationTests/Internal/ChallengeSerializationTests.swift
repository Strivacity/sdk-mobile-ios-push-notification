import Foundation
@_spi(PluginBridge) @testable import PushNotification
import Testing

/// Exercises `serializeChallenge` and `deserializeChallenge`.
struct ChallengeSerializationTests {
    let context = ChallengeContext(
        challengeId: "challenge-1",
        challengeValue: "challenge-value",
        issuer: "https://issuer.example.com",
        accountId: "account-1",
        expiresAt: "2026-10-01T14:30:00Z",
        metadata: ["place": "New York", "device": nil]
    )

    let options = ["12", "26", "84"]

    @Test func aSimpleChallengeRoundTripsToASimpleChallenge() throws {
        let restored = try roundTrip(.simple(Challenge.Simple(context: context)))

        #expect(restored.simple != nil)
    }

    @Test func aContextMatchingChallengeRoundTripsToAContextMatchingChallengeWithItsOptions() throws {
        let restored = try roundTrip(.contextMatching(Challenge.ContextMatching(context: context, options: options)))

        #expect(restored.contextMatching?.options == options)
    }

    @Test func aRestoredChallengeKeepsItsPublicFields() throws {
        let restored = try roundTrip(.simple(Challenge.Simple(context: context)))

        #expect(
            [restored.challengeId, restored.issuer, restored.accountId, restored.expiresAt]
                == [context.challengeId, context.issuer, context.accountId, context.expiresAt]
        )
    }

    @Test func aRestoredChallengeKeepsNilMetadataValues() throws {
        let restored = try roundTrip(.simple(Challenge.Simple(context: context)))

        #expect(restored.metadata == context.metadata)
    }

    @Test func aRestoredChallengeResolvesWithTheOriginalChallengeValue() throws {
        let restored = try roundTrip(.simple(Challenge.Simple(context: context)))

        #expect(restored.simple?.approve().challengeValue == context.challengeValue)
    }

    @Test func aRestoredContextMatchingChallengeStillRejectsAnOptionThatWasNotOffered() throws {
        let restored = try roundTrip(.contextMatching(Challenge.ContextMatching(context: context, options: options)))
        let matching = try #require(restored.contextMatching)

        #expect(throws: PushNotificationError.self) { try matching.select("99") }
    }

    @Test func textThatIsNotASnapshotThrowsChallengeUnavailable() {
        #expect(throws: PushNotificationError.self) { try deserializeChallenge("not json") }
    }

    @Test func anUnreadableSnapshotFailsWithTheChallengeUnavailableCode() throws {
        let failure = try #require(throws: PushNotificationError.self) { try deserializeChallenge("not json") }

        #expect(failure.code == "challenge_unavailable")
    }

    @Test func anUnsupportedSnapshotVersionIsRejected() {
        #expect(throws: PushNotificationError.self) { try deserializeChallenge(snapshot(["version": 2])) }
    }

    @Test func anUnknownChallengeTypeIsRejected() {
        #expect(throws: PushNotificationError.self) { try deserializeChallenge(snapshot(["type": "other"])) }
    }

    @Test func aBlankChallengeIdIsRejected() {
        #expect(throws: PushNotificationError.self) { try deserializeChallenge(snapshot(["challengeId": " "])) }
    }

    @Test func aBlankChallengeValueIsRejected() {
        #expect(throws: PushNotificationError.self) { try deserializeChallenge(snapshot(["challengeValue": ""])) }
    }

    @Test func aBlankIssuerIsRejected() {
        #expect(throws: PushNotificationError.self) { try deserializeChallenge(snapshot(["issuer": ""])) }
    }

    @Test func aBlankAccountIdIsRejected() {
        #expect(throws: PushNotificationError.self) { try deserializeChallenge(snapshot(["accountId": ""])) }
    }

    @Test func aBlankExpiryIsRejected() {
        #expect(throws: PushNotificationError.self) { try deserializeChallenge(snapshot(["expiresAt": ""])) }
    }

    @Test func aSimpleSnapshotThatCarriesOptionsIsRejected() {
        #expect(throws: PushNotificationError.self) { try deserializeChallenge(snapshot(["options": ["1"]])) }
    }

    @Test func aContextMatchingSnapshotWithoutOptionsIsRejected() {
        #expect(throws: PushNotificationError.self) {
            try deserializeChallenge(snapshot(["type": "contextMatching"]))
        }
    }

    @Test func aContextMatchingSnapshotWithEmptyOptionsIsRejected() {
        #expect(throws: PushNotificationError.self) {
            try deserializeChallenge(snapshot(["type": "contextMatching", "options": [String]()]))
        }
    }

    @Test func anUnreadableSnapshotsErrorMessageDoesNotContainTheSnapshotText() throws {
        let failure = try #require(throws: PushNotificationError.self) {
            try deserializeChallenge(snapshot(["version": 2]))
        }

        #expect(!failure.message.contains("challenge-value"))
    }

    @Test func aRestoredChallengesDescriptionDoesNotContainTheChallengeValue() throws {
        let restored = try roundTrip(.simple(Challenge.Simple(context: context)))

        #expect(!restored.description.contains(context.challengeValue))
    }

    @Test func theSharedSnapshotFixtureDecodesToTheExpectedContextMatchingChallenge() throws {
        let restored = try deserializeChallenge(Self.sharedFixture)

        #expect(
            [restored.challengeId, restored.issuer, restored.accountId, restored.expiresAt]
                == ["challenge-1", "https://issuer.example.com", "account-1", "2026-10-01T14:30:00Z"]
        )
    }

    @Test func theSharedSnapshotFixtureKeepsItsOptionsAndMetadata() throws {
        let restored = try deserializeChallenge(Self.sharedFixture)

        #expect(restored.contextMatching?.options == options)
        #expect(restored.metadata == ["place": "New York", "device": nil])
    }

    @Test func theSharedSnapshotFixtureKeepsItsChallengeValue() throws {
        let restored = try deserializeChallenge(Self.sharedFixture)

        #expect(try restored.contextMatching?.select("12").challengeValue == "challenge-value")
    }

    /// A context-matching snapshot; the Android SDK's tests decode the same text.
    static let sharedFixture =
        #"{"version":1,"type":"contextMatching","challengeId":"challenge-1","# +
        #""challengeValue":"challenge-value","issuer":"https://issuer.example.com","# +
        #""accountId":"account-1","expiresAt":"2026-10-01T14:30:00Z","# +
        #""metadata":{"place":"New York","device":null},"options":["12","26","84"]}"#

    private func roundTrip(_ challenge: Challenge) throws -> Challenge {
        try deserializeChallenge(serializeChallenge(challenge))
    }

    /// A simple-challenge snapshot; each override replaces a field's value.
    private func snapshot(_ overrides: [String: Any]) -> String {
        let fields: [String: Any] = [
            "version": 1,
            "type": "simple",
            "challengeId": "challenge-1",
            "challengeValue": "challenge-value",
            "issuer": "https://issuer.example.com",
            "accountId": "account-1",
            "expiresAt": "2026-10-01T14:30:00Z",
            "metadata": [String: String](),
        ].merging(overrides) { _, override in override }

        // Serializing a dictionary of plain JSON values cannot fail.
        // swiftlint:disable:next force_try
        let data = try! JSONSerialization.data(withJSONObject: fields)
        return String(decoding: data, as: UTF8.self)
    }
}

private extension Challenge {
    var simple: Challenge.Simple? {
        switch self {
        case let .simple(challenge): challenge
        case .contextMatching: nil
        }
    }

    var contextMatching: Challenge.ContextMatching? {
        switch self {
        case .simple: nil
        case let .contextMatching(challenge): challenge
        }
    }
}
