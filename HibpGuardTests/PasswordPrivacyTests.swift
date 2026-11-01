import XCTest
@testable import HibpGuard

final class PasswordPrivacyTests: XCTestCase {
    func testKnownSHA1Vector() {
        let value = PasswordFingerprint(password: "password")
        XCTAssertEqual(value.prefix, "5BAA6")
        XCTAssertEqual(value.suffix, "1E4C9B93F3F0682250B6CF8331B7EE68FD8")
        XCTAssertEqual(value.prefix.count, 5)
        XCTAssertEqual(value.suffix.count, 35)
    }

    func testPasswordIsNotTrimmedOrNormalized() {
        XCTAssertNotEqual(PasswordFingerprint(password: " password "), PasswordFingerprint(password: "password"))
        XCTAssertNotEqual(PasswordFingerprint(password: "PASSWORD"), PasswordFingerprint(password: "password"))
        XCTAssertNotEqual(PasswordFingerprint(password: "\u{00E9}"), PasswordFingerprint(password: "e\u{0301}"))
    }

    func testCRLFParsingAndPadding() throws {
        let target = PasswordFingerprint(password: "password").suffix
        let padding = String(repeating: "0", count: 35)
        let body = "\(padding):0\r\n\(target):12345\r\n"
        XCTAssertEqual(try PasswordRangeParser.occurrences(of: target, in: Data(body.utf8)), 12345)
        XCTAssertEqual(try PasswordRangeParser.occurrences(of: padding, in: Data(body.utf8)), 0)
    }

    func testAbsentSuffixIsZeroOnlyForValidResponse() throws {
        let target = PasswordFingerprint(password: "password").suffix
        let other = String(repeating: "A", count: 35)
        XCTAssertEqual(try PasswordRangeParser.occurrences(of: target, in: Data("\(other):15\n".utf8)), 0)
    }

    func testMalformedResponsesNeverLookLikeCleanPasswords() {
        let target = PasswordFingerprint(password: "password").suffix
        let invalid = ["", "<html>Service unavailable</html>", "\(target):-1\n",
                       "NOT-A-HASH:12\n", "\(target):9999999999999999999999999\n",
                       "\(target):1:2\n", "\(target):1\n\(target):2\n",
                       "\(target):1\nBAD-ROW\n"]
        for body in invalid {
            XCTAssertThrowsError(try PasswordRangeParser.occurrences(of: target, in: Data(body.utf8))) {
                XCTAssertEqual($0 as? AppError, .invalidResponse)
            }
        }
    }
}
