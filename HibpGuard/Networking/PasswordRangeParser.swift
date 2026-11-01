import Foundation

enum PasswordRangeParser {
    static func occurrences(of expectedSuffix: String, in data: Data) throws -> Int {
        guard expectedSuffix.count == 35, isHex(expectedSuffix),
              let body = String(data: data, encoding: .utf8) else {
            throw AppError.invalidResponse
        }
        let lines = body.split(whereSeparator: { $0.isNewline })
        guard !lines.isEmpty else { throw AppError.invalidResponse }
        var match: Int?
        for line in lines {
            let fields = line.split(separator: ":", omittingEmptySubsequences: false)
            guard fields.count == 2, fields[0].count == 35,
                  isHex(fields[0]), !fields[1].isEmpty,
                  fields[1].utf8.allSatisfy({ (48...57).contains($0) }),
                  let count = Int(fields[1]) else {
                // An HTML error page must never be interpreted as "not found".
                throw AppError.invalidResponse
            }
            if fields[0].uppercased() == expectedSuffix.uppercased() {
                guard match == nil else { throw AppError.invalidResponse }
                match = count
            }
            // Add-Padding rows have count 0 and do not indicate a breach.
        }
        return match ?? 0
    }

    private static func isHex<S: StringProtocol>(_ value: S) -> Bool {
        value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }
}
