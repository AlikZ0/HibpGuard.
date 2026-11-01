import Foundation
import Combine

@MainActor
final class PasswordCheckViewModel: ObservableObject {
    @Published var password = "" { didSet { if password != oldValue { invalidate() } } }
    @Published private(set) var state: CheckState<Int> = .idle
    @Published private(set) var retryNotBefore: Date?
    private let service: any PasswordChecking
    private var task: Task<Void, Never>?
    private var requestID = UUID()

    init(service: any PasswordChecking) { self.service = service }

    func canCheck(at date: Date) -> Bool {
        !state.isLoading && (retryNotBefore.map { date >= $0 } ?? true)
    }

    @discardableResult
    func check() -> Task<Void, Never>? {
        guard canCheck(at: Date()) else { return nil }
        guard !password.isEmpty else { state = .failure(.emptyPassword); return nil }
        let fingerprint = PasswordFingerprint(password: password)
        password = "" // Clear before creating an async task; never capture the password.
        let id = UUID()
        requestID = id
        state = .loading
        let work = Task { [weak self] in
            guard let self else { return }
            do {
                let count = try await self.service.occurrences(for: fingerprint)
                try Task.checkCancellation()
                guard self.requestID == id else { return }
                self.state = .success(count)
            } catch is CancellationError {
                guard self.requestID == id else { return }
                self.state = .idle
            } catch {
                guard self.requestID == id else { return }
                let appError = error as? AppError ?? .unexpected
                if case .rateLimited(let until) = appError { self.retryNotBefore = until }
                self.state = .failure(appError)
            }
            if self.requestID == id { self.task = nil }
        }
        task = work
        return work
    }

    func invalidate() {
        requestID = UUID()
        task?.cancel()
        task = nil
        state = .idle
    }

    func clearSensitiveState() {
        invalidate()
        password = ""
    }
}
