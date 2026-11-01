import XCTest
@testable import HibpGuard

actor RecordingTransport: HTTPTransport {
    private let status: Int
    private let body: Data
    private let headers: [String: String]
    private(set) var lastRequest: URLRequest?

    init(status: Int = 200, body: String = "", headers: [String: String] = [:]) {
        self.status = status
        self.body = Data(body.utf8)
        self.headers = headers
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status,
                                             httpVersion: "HTTP/1.1", headerFields: headers) else {
            throw AppError.invalidResponse
        }
        return (body, response)
    }
}

private struct FailingTransport: HTTPTransport {
    let code: URLError.Code
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(code)
    }
}

final class NetworkingTests: XCTestCase {
    func testEmailRequestsFullModelAndEncodesReservedCharacters() async throws {
        let body = """
        [{"Name":"Example","Title":"Example service","BreachDate":"2025-01-02",
          "DataClasses":["Passwords"],"IsVerified":true}]
        """
        let transport = RecordingTransport(body: body)
        let client = HIBPClient(transport: transport)
        let result = try await client.breaches(for: "a+b/?#%@example.com", apiKey: "example-key")
        XCTAssertEqual(result.first?.dataClasses, ["Passwords"])
        XCTAssertEqual(result.first?.breachDate, "2025-01-02")
        let captured = await transport.lastRequest
        let request = try XCTUnwrap(captured)
        let url = try XCTUnwrap(request.url)
        XCTAssertTrue(url.absoluteString.contains("a%2Bb%2F%3F%23%25%40example.com"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "truncateResponse", value: "false")])
        XCTAssertEqual(request.value(forHTTPHeaderField: "hibp-api-key"), "example-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "HibpGuard/1.0 (iOS)")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testEmail404MeansNoMatches() async throws {
        let client = HIBPClient(transport: RecordingTransport(status: 404))
        let result = try await client.breaches(for: "example@example.com", apiKey: "example-key")
        XCTAssertTrue(result.isEmpty)
    }

    func testPasswordRequestContainsOnlyPrefixAndEnablesPadding() async throws {
        let fingerprint = PasswordFingerprint(password: "password")
        let transport = RecordingTransport(body: "\(fingerprint.suffix):123\r\n")
        let client = HIBPClient(transport: transport)
        let count = try await client.passwordOccurrences(for: fingerprint)
        XCTAssertEqual(count, 123)
        let captured = await transport.lastRequest
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://api.pwnedpasswords.com/range/5BAA6")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "hibp-api-key"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Add-Padding"), "true")
        XCTAssertFalse(request.url?.absoluteString.contains(fingerprint.suffix) ?? true)
        XCTAssertFalse(request.url?.absoluteString.contains("password/") ?? true)
    }

    func testPassword404IsAnError() async {
        let client = HIBPClient(transport: RecordingTransport(status: 404))
        do {
            _ = try await client.passwordOccurrences(for: PasswordFingerprint(password: "password"))
            XCTFail("A range API error must not produce a clean result")
        } catch { XCTAssertEqual(error as? AppError, .httpStatus(404)) }
    }

    func testAuthorizationAndServiceErrorsStayErrors() async {
        let cases: [(Int, AppError)] = [(401, .invalidAPIKey), (403, .forbidden), (503, .httpStatus(503))]
        for (status, expected) in cases {
            let client = HIBPClient(transport: RecordingTransport(status: status))
            do {
                _ = try await client.breaches(for: "example@example.com", apiKey: "example-key")
                XCTFail("Expected HTTP error")
            } catch { XCTAssertEqual(error as? AppError, expected) }
        }
    }

    func test429CarriesRetryAfter() async {
        let transport = RecordingTransport(status: 429, headers: ["Retry-After": "60"])
        let client = HIBPClient(transport: transport)
        do {
            _ = try await client.breaches(for: "example@example.com", apiKey: "example-key")
            XCTFail("Expected rate limit")
        } catch let AppError.rateLimited(until) {
            XCTAssertNotNil(until)
            XCTAssertEqual(until?.timeIntervalSinceNow ?? 0, 60, accuracy: 2)
        } catch { XCTFail("Unexpected error type") }
    }

    func testInvalidJSONDoesNotProduceCleanEmailResult() async {
        let client = HIBPClient(transport: RecordingTransport(body: "[{\"Name\":\"OnlyTruncatedName\"}]"))
        do {
            _ = try await client.breaches(for: "example@example.com", apiKey: "example-key")
            XCTFail("Missing full-model fields must fail decoding")
        } catch { XCTAssertEqual(error as? AppError, .invalidResponse) }
    }

    func testTimeoutHasSafeUserMessage() async {
        let client = HIBPClient(transport: FailingTransport(code: .timedOut))
        do {
            _ = try await client.breaches(for: "private@example.com", apiKey: "example-key")
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? AppError, .timeout)
            XCTAssertFalse((error as? AppError)?.message.contains("private@example.com") ?? true)
        }
    }

    func testCancellationIsPreserved() async {
        let client = HIBPClient(transport: FailingTransport(code: .cancelled))
        do {
            _ = try await client.passwordOccurrences(for: PasswordFingerprint(password: "password"))
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testRetryAfterFormats() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(RetryAfter.deadline(header: "42", now: now), now.addingTimeInterval(42))
        XCTAssertEqual(RetryAfter.deadline(header: "Thu, 01 Jan 1970 00:20:00 GMT", now: now),
                       Date(timeIntervalSince1970: 1_200))
        XCTAssertEqual(RetryAfter.deadline(header: "Thu, 01 Jan 1970 00:00:00 GMT", now: now), now)
        for header in [nil, "", "-2", "NaN", "inf", "not-a-date"] as [String?] {
            XCTAssertNil(RetryAfter.deadline(header: header, now: now))
        }
    }
}
