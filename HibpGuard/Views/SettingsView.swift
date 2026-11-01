import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Ваш API-ключ HIBP") {
                    Label(viewModel.hasSavedKey ? "Ключ сохранён" : "Ключ не добавлен",
                          systemImage: viewModel.hasSavedKey ? "key.fill" : "key")
                    SecureField("32 шестнадцатеричных символа", text: $viewModel.key)
                        .keyboardType(.asciiCapable)
                        .textContentType(nil)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .accessibilityLabel("Новый API-ключ HIBP")
                    Button("Сохранить в Keychain") { viewModel.save() }
                        .disabled(viewModel.key.isEmpty)
                    if viewModel.hasSavedKey {
                        Button("Удалить ключ", role: .destructive) { confirmDelete = true }
                    }
                    if let message = viewModel.message {
                        Text(message).foregroundStyle(viewModel.isError ? Color.orange : Color.secondary)
                    }
                }
                Section {
                    Text("Ключ доступен только на разблокированном устройстве, не синхронизируется через iCloud Keychain и не переносится на другое устройство.")
                    Text("Используйте собственный ключ. Для публичного приложения с общей подпиской храните ключ на вашем сервере.")
                    Text("Проверка паролей бесплатна и работает без API-ключа.")
                    Link("API и подписка HIBP", destination: URL(string: "https://haveibeenpwned.com/API/Key")!)
                }.font(.footnote)
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .onAppear { viewModel.refresh() }
            .onDisappear { viewModel.clearDraft() }
            .confirmationDialog("Удалить API-ключ с устройства?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { viewModel.delete() }
            }
        }
    }
}

#Preview { SettingsView(viewModel: SettingsViewModel(keyStore: KeychainAPIKeyStore())) }
