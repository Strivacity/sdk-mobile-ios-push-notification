import Foundation
@testable import PushNotification

extension URLRequest {
    /// `httpBody` can arrive as `httpBodyStream` instead, depending on how `URLSession` chose to
    /// dispatch the request — `URLProtocol` sees whichever one it picked, not necessarily the one
    /// the caller set.
    func bodyData() throws -> Data {
        if let body = httpBody {
            return body
        }
        guard let stream = httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    func bodyText() throws -> String {
        guard let text = try String(data: bodyData(), encoding: .utf8) else {
            throw TestFailure("request body is not valid UTF-8")
        }
        return text
    }

    /// Alias for `bodyText()`, used when the whole body is a signed JWT.
    func jwtBody() throws -> String {
        try bodyText()
    }

    func jwtHeaderClaims() throws -> [String: String] {
        try jwtSegment(0)
    }

    func jwtPayloadClaims() throws -> [String: String] {
        try jwtSegment(1)
    }

    private func jwtSegment(_ index: Int) throws -> [String: String] {
        let segments = try jwtBody().split(separator: ".", omittingEmptySubsequences: false)
        guard segments.indices.contains(index) else {
            throw TestFailure("JWT body has no segment \(index)")
        }
        guard let data = Base64Url.decode(String(segments[index])) else {
            throw TestFailure("JWT segment \(index) is not valid base64url")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw TestFailure("JWT segment \(index) is not a flat JSON object of strings")
        }
        return object
    }
}
