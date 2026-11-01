import XCTest
import Security
@testable import HibpGuard

private final class MemoryChecklistStorage: ChecklistStorage {
    var value: Set<String> = []
    var failsSaving = false
    func load() throws -> Set<String> { value }
    func save(_ completedIDs: Set<String>) throws {
        if failsSaving { throw AppError.storage }
        value = completedIDs
    }
}

final class StorageTests: XCTestCase {
    func testKeychainRoundTripAndAccessibility() throws {
        let service = "HibpGuardTests." + UUID().uuidString
        let store = KeychainAPIKeyStore(service: service)
        defer { try? store.deleteAPIKey() }
        XCTAssertNil(try store.readAPIKey())
        try store.saveAPIKey(String(repeating: "a", count: 32))
        XCTAssertEqual(try store.readAPIKey(), String(repeating: "a", count: 32))
        try store.saveAPIKey(String(repeating: "b", count: 32))
        XCTAssertEqual(try store.readAPIKey(), String(repeating: "b", count: 32))
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: "hibp-api-key",
                                    kSecReturnAttributes as String: true]
        var item: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &item), errSecSuccess)
        let attributes = try XCTUnwrap(item as? [String: Any])
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        try store.deleteAPIKey()
        XCTAssertNil(try store.readAPIKey())
    }

    func testChecklistFileRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FileChecklistStorage(url: directory.appendingPathComponent("checklist.json"))
        XCTAssertTrue(try storage.load().isEmpty)
        try storage.save(["devices", "enable-2fa"])
        XCTAssertEqual(try storage.load(), ["devices", "enable-2fa"])
    }

    @MainActor
    func testChecklistSurvivesRecreatingStore() {
        let storage = MemoryChecklistStorage()
        let first = ActionPlanStore(storage: storage)
        first.toggle("devices")
        let reopened = ActionPlanStore(storage: storage)
        XCTAssertTrue(reopened.completedIDs.contains("devices"))
    }

    @MainActor
    func testFailedWriteDoesNotShowUnsavedCheckmark() {
        let storage = MemoryChecklistStorage()
        storage.failsSaving = true
        let model = ActionPlanStore(storage: storage)
        model.toggle("devices")
        XCTAssertFalse(model.completedIDs.contains("devices"))
        XCTAssertEqual(model.error, .storage)
    }

    @MainActor
    func testUnknownActionIDsAreIgnored() {
        let storage = MemoryChecklistStorage()
        storage.value = ["devices", "removed-action"]
        let model = ActionPlanStore(storage: storage)
        XCTAssertEqual(model.completedIDs, ["devices"])
    }
}
