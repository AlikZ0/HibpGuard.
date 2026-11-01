import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var key = ""
    @Published private(set) var hasSavedKey = false
    @Published private(set) var message: String?
    @Published private(set) var isError = false
    private let keyStore: any APIKeyStoring

    init(keyStore: any APIKeyStoring) { self.keyStore = keyStore }

    func refresh() {
        do {
            hasSavedKey = try keyStore.readAPIKey() != nil
            message = nil
            isError = false
        } catch { showError(error) }
    }

    func save() {
        let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.utf8.count == 32, candidate.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) else {
            isError = true
            message = "Ключ HIBP должен содержать 32 шестнадцатеричных символа."
            return
        }
        do {
            try keyStore.saveAPIKey(candidate)
            key = ""
            hasSavedKey = true
            isError = false
            message = "Ключ сохранён. Его действительность проверится при запросе к HIBP."
        } catch { showError(error) }
    }

    func delete() {
        do {
            try keyStore.deleteAPIKey()
            key = ""
            hasSavedKey = false
            isError = false
            message = "Ключ удалён."
        } catch { showError(error) }
    }

    func clearDraft() { key = "" }

    private func showError(_ error: Error) {
        isError = true
        message = (error as? AppError ?? .unexpected).message
    }
}
