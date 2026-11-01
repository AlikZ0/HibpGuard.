import Foundation
import Combine

@MainActor
final class AppContainer: ObservableObject {
    let email: EmailCheckViewModel
    let password: PasswordCheckViewModel
    let settings: SettingsViewModel
    let actionPlan: ActionPlanStore

    init() {
        let client = HIBPClient()
        let keyStore = KeychainAPIKeyStore()
        email = EmailCheckViewModel(live: LiveEmailService(client: client, keyStore: keyStore))
        password = PasswordCheckViewModel(service: LivePasswordService(client: client))
        settings = SettingsViewModel(keyStore: keyStore)
        actionPlan = ActionPlanStore()
    }

    func clearSensitiveState() {
        email.clearSensitiveState()
        password.clearSensitiveState()
        settings.clearDraft()
    }
}
