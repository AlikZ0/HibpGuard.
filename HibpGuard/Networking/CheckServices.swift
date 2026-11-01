import Foundation

protocol EmailChecking: Sendable {
    func breaches(for email: String) async throws -> [Breach]
}

protocol PasswordChecking: Sendable {
    func occurrences(for fingerprint: PasswordFingerprint) async throws -> Int
}

struct LiveEmailService: EmailChecking {
    let client: HIBPClient
    let keyStore: any APIKeyStoring

    func breaches(for email: String) async throws -> [Breach] {
        guard let key = try keyStore.readAPIKey(), !key.isEmpty else {
            throw AppError.missingAPIKey
        }
        return try await client.breaches(for: email, apiKey: key)
    }
}

struct LivePasswordService: PasswordChecking {
    let client: HIBPClient

    func occurrences(for fingerprint: PasswordFingerprint) async throws -> Int {
        try await client.passwordOccurrences(for: fingerprint)
    }
}

/// Never calls a server. The screen explicitly labels all results as demo data.
struct MockEmailService: EmailChecking {
    func breaches(for email: String) async throws -> [Breach] {
        try Task.checkCancellation()
        if email.lowercased() == "clean@example.com" { return [] }
        return [Breach(name: "DemoService", title: "Пример сервиса (демо)",
                       breachDate: "2025-04-18", dataClasses: ["Email addresses", "Passwords"],
                       isVerified: true)]
    }
}
