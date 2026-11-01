import XCTest
@testable import HibpGuard

private struct FixedPasswordService: PasswordChecking {
    let result: Int
    func occurrences(for fingerprint: PasswordFingerprint) async throws -> Int { result }
}

private struct BrokenPasswordService: PasswordChecking {
    func occurrences(for fingerprint: PasswordFingerprint) async throws -> Int { throw AppError.network }
}

/// Intentionally ignores cancellation: the view model must reject late results.
private actor GatedPasswordService: PasswordChecking {
    private var answer: CheckedContinuation<Int, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func occurrences(for fingerprint: PasswordFingerprint) async throws -> Int {
        await withCheckedContinuation { continuation in
            answer = continuation
            startWaiters.forEach { $0.resume() }
            startWaiters = []
        }
    }

    func waitUntilStarted() async {
        if answer != nil { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish(count: Int) {
        answer?.resume(returning: count)
        answer = nil
    }
}

final class ViewModelTests: XCTestCase {
    @MainActor
    func testPasswordFieldClearsBeforeRequestCompletes() async {
        let service = GatedPasswordService()
        let model = PasswordCheckViewModel(service: service)
        model.password = "password"
        let task = model.check()
        XCTAssertEqual(model.password, "")
        XCTAssertTrue(model.state.isLoading)
        await service.waitUntilStarted()
        await service.finish(count: 123)
        await task?.value
        guard case .success(let count) = model.state else { return XCTFail("Expected result") }
        XCTAssertEqual(count, 123)
    }

    @MainActor
    func testOldResultCannotOverwriteChangedInput() async {
        let service = GatedPasswordService()
        let model = PasswordCheckViewModel(service: service)
        model.password = "password"
        let task = model.check()
        await service.waitUntilStarted()
        model.password = "new input"
        await service.finish(count: 999)
        await task?.value
        guard case .idle = model.state else { return XCTFail("Stale result was published") }
    }

    @MainActor
    func testBackgroundClearingCancelsPendingResult() async {
        let service = GatedPasswordService()
        let model = PasswordCheckViewModel(service: service)
        model.password = "password"
        let task = model.check()
        await service.waitUntilStarted()
        model.clearSensitiveState()
        await service.finish(count: 999)
        await task?.value
        XCTAssertEqual(model.password, "")
        guard case .idle = model.state else { return XCTFail("Background result was published") }
    }

    @MainActor
    func testNetworkFailureNeverBecomesZero() async {
        let model = PasswordCheckViewModel(service: BrokenPasswordService())
        model.password = "password"
        await model.check()?.value
        guard case .failure(let error) = model.state else { return XCTFail("Expected failure") }
        XCTAssertEqual(error, .network)
    }

    @MainActor
    func testEmptyPasswordDoesNotStartRequest() {
        let model = PasswordCheckViewModel(service: FixedPasswordService(result: 1))
        XCTAssertNil(model.check())
        guard case .failure(let error) = model.state else { return XCTFail("Expected input error") }
        XCTAssertEqual(error, .emptyPassword)
    }

    @MainActor
    func testChangingDemoModeInvalidatesDisplayedResult() async {
        let model = EmailCheckViewModel(live: MockEmailService())
        model.email = "example@example.com"
        await model.check()?.value
        guard case .success = model.state else { return XCTFail("Expected demo result") }
        model.useDemo = false
        guard case .idle = model.state else { return XCTFail("Demo result remained visible in live mode") }
    }

    @MainActor
    func testInvalidEmailIsRejected() {
        let model = EmailCheckViewModel(live: MockEmailService())
        model.email = "not-an-email"
        XCTAssertNil(model.check())
        guard case .failure(let error) = model.state else { return XCTFail("Expected input error") }
        XCTAssertEqual(error, .invalidEmail)
    }
}
