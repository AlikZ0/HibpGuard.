import Foundation

struct HIBPClient: Sendable {
    private let transport: any HTTPTransport
    private let userAgent = "HibpGuard/1.0 (iOS)"

    init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    func breaches(for email: String, apiKey: String) async throws -> [Breach] {
        // Encode the whole email as ONE path component, including +, /, ? and #.
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let encoded = email.addingPercentEncoding(withAllowedCharacters: safe) else {
            throw AppError.invalidEmail
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "haveibeenpwned.com"
        components.percentEncodedPath = "/api/v3/breachedaccount/" + encoded
        components.queryItems = [URLQueryItem(name: "truncateResponse", value: "false")]
        guard let url = components.url else { throw AppError.invalidEmail }
        var request = makeRequest(url: url, accept: "application/json")
        request.setValue(apiKey, forHTTPHeaderField: "hibp-api-key")
        let (data, response) = try await send(request)
        if response.statusCode == 404 { return [] }
        try validate(response)
        do {
            return try JSONDecoder().decode([Breach].self, from: data)
                .sorted { $0.breachDate > $1.breachDate }
        } catch {
            throw AppError.invalidResponse
        }
    }

    func passwordOccurrences(for fingerprint: PasswordFingerprint) async throws -> Int {
        // Only this 5-character prefix crosses the network boundary.
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.pwnedpasswords.com"
        components.path = "/range/" + fingerprint.prefix
        guard let url = components.url else { throw AppError.invalidResponse }
        var request = makeRequest(url: url, accept: "text/plain")
        request.setValue("true", forHTTPHeaderField: "Add-Padding")
        let (data, response) = try await send(request)
        // Every valid password range returns 200, so 404 here is an error.
        try validate(response)
        return try PasswordRangeParser.occurrences(of: fingerprint.suffix, in: data)
    }

    private func makeRequest(url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let result = try await transport.data(for: request)
            try Task.checkCancellation()
            guard result.0.count <= 2 * 1024 * 1024 else { throw AppError.invalidResponse }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw AppError.timeout
            default: throw AppError.network
            }
        } catch let error as AppError {
            throw error
        } catch {
            // Do not surface URLSession descriptions: they can contain the email URL.
            throw AppError.network
        }
    }

    private func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200: return
        case 400: throw AppError.httpStatus(400)
        case 401: throw AppError.invalidAPIKey
        case 403: throw AppError.forbidden
        case 429:
            throw AppError.rateLimited(until: RetryAfter.deadline(
                header: response.value(forHTTPHeaderField: "Retry-After")))
        default: throw AppError.httpStatus(response.statusCode)
        }
    }
}
