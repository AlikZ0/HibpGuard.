import Foundation
import CryptoKit

struct PasswordFingerprint: Equatable, Sendable {
    let prefix: String
    let suffix: String

    init(password: String) {
        // SHA-1 is required by Pwned Passwords; it is NOT used for password storage.
        // Do not trim, lowercase or Unicode-normalize a password.
        let digest = Insecure.SHA1.hash(data: Data(password.utf8))
        let hex = digest.map { String(format: "%02X", $0) }.joined()
        prefix = String(hex.prefix(5))
        suffix = String(hex.dropFirst(5))
    }
}
