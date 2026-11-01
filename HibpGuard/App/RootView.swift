import SwiftUI

private enum AppTab: Hashable {
    case email, password, actions
    var title: String {
        switch self {
        case .email: return "Проверка email"
        case .password: return "Проверка пароля"
        case .actions: return "План действий"
        }
    }
}

struct RootView: View {
    @ObservedObject var container: AppContainer
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected: AppTab = .email
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            TabView(selection: $selected) {
                EmailCheckView(viewModel: container.email, showPlan: { selected = .actions },
                               showSettings: { showSettings = true })
                    .tabItem { Label("Email", systemImage: "envelope") }.tag(AppTab.email)
                PasswordCheckView(viewModel: container.password, showPlan: { selected = .actions })
                    .tabItem { Label("Пароль", systemImage: "lock") }.tag(AppTab.password)
                ActionPlanView(store: container.actionPlan)
                    .tabItem { Label("Действия", systemImage: "checklist") }.tag(AppTab.actions)
            }
            .navigationTitle(selected.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Настройки API-ключа")
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView(viewModel: container.settings) }
        .overlay {
            if scenePhase != .active {
                ZStack {
                    Color(uiColor: .systemBackground).ignoresSafeArea()
                    Label("HibpGuard", systemImage: "lock.shield").font(.title)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { container.clearSensitiveState() }
            if phase == .active { container.actionPlan.reload() }
        }
        .onChange(of: selected) { _, _ in
            // An unfinished password check must not outlive its screen.
            container.password.clearSensitiveState()
        }
    }
}

#Preview { RootView(container: AppContainer()) }
