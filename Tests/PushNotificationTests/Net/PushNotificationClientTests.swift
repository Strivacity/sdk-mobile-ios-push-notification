import Foundation
@testable import PushNotification
import Testing

/// Exercises paths not covered by higher-level tests:
/// - the constructor's default path (a real `URLSession`);
/// - the challengeId path-injection defense.
///
/// Also the first suite to exercise the `mockSession`/`MockURLProtocol` harness end to end, ahead
/// of the full `PushNotification`-facade suites layered on top of it.
struct PushNotificationClientTests {
    @Test func constructingWithNoSessionSucceeds() {
        // No network call is made; constructing the client doesn't make one.
        _ = PushNotificationClient()
    }

    // --- challengeId can't restructure the request ---

    @Test func aChallengeIdContainingPathAndQuerySyntaxStaysOneOpaquePathSegment() async throws {
        let capturedRequest = LockedBox<URLRequest>()
        let client = PushNotificationClient(session: mockSession { request in
            capturedRequest.value = request
            return respondJson(
                for: request,
                body: #"{"expireAt":"2026-10-01T14:30:00Z","metadata":{},"action":{"type":"simple"}}"#
            )
        })
        let maliciousChallengeId = "../other-issuer/../../evil?injected=1#frag"

        // Only the outgoing request matters here, not the parsed response.
        _ = try? await client.challenge(
            normalizedIssuer: "https://issuer.example.com",
            challengeId: maliciousChallengeId
        )

        let url = try #require(capturedRequest.value?.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "issuer.example.com")
        #expect(components
            .percentEncodedPath ==
            "/pushNotification/api/v1/actions/..%2Fother-issuer%2F..%2F..%2Fevil%3Finjected=1%23frag")
        #expect(components.queryItems == nil, "no query parameter should have been injected")
        #expect(components.fragment == nil, "no fragment should have been injected")
    }
}
