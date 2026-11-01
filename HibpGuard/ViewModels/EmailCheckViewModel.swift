import Foundation
import Combine

@MainActor
final class EmailCheckViewModel: ObservableObject {
    @Published var email = "" { didSet { if email != oldValue { invalidate() } } }
    @Published var useDemo = true { didSet { if useDemo != oldValue { invalidate() } } }
    @Published private(set) var state: CheckState<[Breach]> = .idle
    @Published private(set) var retryNotBefore: Date?
    private let live: any EmailChecking
    private let demo: any EmailChecking
    private var task: Task<Void, Never>?
    private var requestID = UUID()

    init(live: any EmailChecking, demo: any EmailChecking = MockEmailService()) {
        self.live = live
        self.demo = demo
    }

    func canCheck(at date: Date) -> Bool {
        !state.isLoading && (useDemo || retryNotBefore.map { date >= $0 } ?? true)
    }

    @discardableResult
    func check() -> Task<Void, Never>? {
        guard canCheck(at: Date()) else { return nil }
        invalidate()
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isPlausibleEmail(normalized) else { state = .failure(.invalidEmail); return nil }
        let service = useDemo ? demo : live
        let id = UUID()
        requestID = id
        state = .loading
        let work = Task { [weak self] in
            guard let self else { return }
            do {
                let breaches = try await service.breaches(for: normalized)
                try Task.checkCancellation()
                guard self.requestID == id else { return }
                self.state = .success(breaches)
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
        // Keep the server cooldown even if the email or mode changes.
    }

    func clearSensitiveState() {
        invalidate()
        email = ""
    }

    private static func isPlausibleEmail(_ value: String) -> Bool {
        // Pragmatic UI validation, not a claim to implement all of RFC 5322.
        guard value.utf8.count <= 254, !value.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            return false
        }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[0].utf8.count <= 64
            && parts[1].contains(".") && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
    }
}
