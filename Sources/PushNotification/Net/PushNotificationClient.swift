import Foundation

/// Everything the SDK says to the backend.
///
/// Every path is rooted at the issuer, under `/pushNotification/api/v1`. Resolution,
/// un-enrollment, and token updates send a signed JWT as the entire request body,
/// `Content-Type: application/jwt`.
///
/// Every call is attempted once. A failure — transport or backend — is surfaced immediately as
/// that call's error; retrying, if wanted, is the caller's decision.
///
/// Request and response bodies are not logged.
struct PushNotificationClient {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForResource = Self.requestTimeout
            self.session = URLSession(configuration: configuration)
        }
    }

    func enroll(normalizedIssuer: String, oneTimeToken: String, request enrollRequest: EnrollRequest) async throws {
        var urlRequest = try request(.post, "\(normalizedIssuer.pushNotificationApi())/enroll")
        urlRequest.setValue("Bearer \(oneTimeToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(enrollRequest)

        let result = try await perform(urlRequest, operation: "enrollment")
        guard result.isSuccess else {
            throw PushNotificationError.enrollmentRejected(
                message: "Enrollment was refused by the backend",
                status: result.status,
                cause: nil
            )
        }
    }

    func unenroll(normalizedIssuer: String, unenrollJwt: String) async throws {
        let urlRequest = try jwtRequest(.post, "\(normalizedIssuer.pushNotificationApi())/unenroll", jwt: unenrollJwt)
        let result = try await perform(urlRequest, operation: "un-enrollment")
        guard result.isSuccess else {
            throw PushNotificationError.unenrollmentRejected(
                message: "Un-enrollment was refused by the backend",
                status: result.status,
                cause: nil
            )
        }
    }

    func challenge(normalizedIssuer: String, challengeId: String) async throws -> ChallengeResponse {
        // challengeId is opaque to the SDK — backend-generated, never validated. It is
        // percent-encoded as exactly one path segment below.
        let urlRequest = try request(
            .get,
            "\(normalizedIssuer.pushNotificationApi())/actions/\(challengeId.percentEncodedForPathSegment())"
        )
        let result = try await perform(urlRequest, operation: "challenge retrieval")
        guard result.isSuccess else {
            throw PushNotificationError.challengeUnavailable(
                message: "Challenge '\(challengeId)' could not be retrieved",
                status: result.status,
                cause: nil
            )
        }

        do {
            return try JSONDecoder().decode(ChallengeResponse.self, from: result.body)
        } catch {
            throw PushNotificationError.challengeUnavailable(
                message: "Challenge '\(challengeId)' was returned in a shape this SDK cannot read",
                status: result.status,
                cause: error
            )
        }
    }

    /// - Returns: whether the backend accepted the resolution. A recorded denial is accepted.
    func resolve(normalizedIssuer: String, challengeId: String, resolutionJwt: String) async throws -> Bool {
        let urlRequest = try jwtRequest(
            .post,
            "\(normalizedIssuer.pushNotificationApi())/actions/\(challengeId.percentEncodedForPathSegment())/submit",
            jwt: resolutionJwt
        )
        let result = try await perform(urlRequest, operation: "resolution")

        if result.isSuccess {
            return true
        }
        if Self.rejectionStatuses.contains(result.status) {
            return false
        }
        throw PushNotificationError.challengeUnavailable(
            message: "Resolution of challenge '\(challengeId)' failed",
            status: result.status,
            cause: nil
        )
    }

    func updateToken(normalizedIssuer: String, updateTokenJwt: String) async throws {
        let urlRequest = try jwtRequest(
            .post,
            "\(normalizedIssuer.pushNotificationApi())/updateToken",
            jwt: updateTokenJwt
        )
        let result = try await perform(urlRequest, operation: "token update")
        guard result.isSuccess else {
            throw PushNotificationError.tokenUpdateRejected(
                message: "Token update was refused by the backend",
                status: result.status,
                cause: nil
            )
        }
    }

    // MARK: - Request/response plumbing

    private func request(_ method: HTTPMethod, _ path: String) throws -> URLRequest {
        guard let url = URL(string: path) else {
            throw PushNotificationError.networkFailure(message: "Could not construct a request URL", cause: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        return request
    }

    private func jwtRequest(_ method: HTTPMethod, _ path: String, jwt: String) throws -> URLRequest {
        var request = try request(method, path)
        request.setValue(Self.jwtContentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(jwt.utf8)
        return request
    }

    private func perform(_ urlRequest: URLRequest, operation: String) async throws -> HTTPResult {
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PushNotificationError.networkFailure(
                    message: "The backend returned a non-HTTP response during \(operation)",
                    cause: nil
                )
            }
            return HTTPResult(status: httpResponse.statusCode, body: data)
        } catch let error as PushNotificationError {
            throw error
        } catch {
            throw PushNotificationError.networkFailure(
                message: "The backend could not be reached during \(operation)",
                cause: error
            )
        }
    }

    private static let requestTimeout: TimeInterval = 30
    /// Statuses treated as a refusal rather than a transport failure.
    private static let rejectionStatuses: Set<Int> = [400, 401, 404]
    private static let jwtContentType = "application/jwt"
}

private enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

private struct HTTPResult {
    let status: Int
    let body: Data

    var isSuccess: Bool {
        (200 ..< 300).contains(status)
    }
}

private extension String {
    /// The issuer's base URL with the fixed API path rooted onto it.
    func pushNotificationApi() -> String {
        "\(self)/pushNotification/api/v1"
    }

    /// Percent-encodes `self` for inclusion as exactly one path segment — encoding `/` too,
    /// unlike `.urlPathAllowed` alone, so a value containing `/`, `?`, or `#` can't inject
    /// additional path segments, a query, or a fragment into the request.
    func percentEncodedForPathSegment() throws -> String {
        guard let encoded = addingPercentEncoding(withAllowedCharacters: Self.pathSegmentAllowedCharacters) else {
            throw PushNotificationError.networkFailure(message: "Could not construct a request URL", cause: nil)
        }
        return encoded
    }

    private static let pathSegmentAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()
}
