import SwiftUI

struct PasswordCheckView: View {
    @ObservedObject var viewModel: PasswordCheckViewModel
    let showPlan: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Form {
                Section {
                    StatusCard(title: "Проверка по частичному хэшу",
                               detail: "Пароль проверяется локально. На сервер отправляются только первые 5 символов SHA-1-хэша. Совпадение с ответом определяется на устройстве.",
                               symbol: "lock.shield", color: .blue)
                    Text("Сервис также видит IP-адрес и время запроса. Проверка запускается только по нажатию кнопки.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Пароль") {
                    SecureField("Введите пароль", text: $viewModel.password)
                        .textContentType(nil)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .submitLabel(.search)
                        .onSubmit { check() }
                        .privacySensitive()
                        .disabled(viewModel.state.isLoading)
                        .accessibilityLabel("Пароль для проверки утечек")
                    Button(action: check) {
                        HStack {
                            if viewModel.state.isLoading { ProgressView() }
                            Text(viewModel.state.isLoading ? "Проверяем…" : "Проверить пароль")
                        }.frame(maxWidth: .infinity)
                    }
                    .disabled(!viewModel.canCheck(at: context.date))
                    if let until = viewModel.retryNotBefore, until > context.date {
                        Text("Повторить можно через \(Int(ceil(until.timeIntervalSince(context.date)))) сек. (Retry-After)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if viewModel.state.isLoading {
                        Button("Отменить", role: .cancel) { viewModel.invalidate() }
                    }
                    Text("Поле очищается при запуске проверки. Пароль и полный хэш не сохраняются.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                resultSection

                Section {
                    HIBPAttribution()
                    Text("Количество показывает, сколько раз пароль встречается в наборе Pwned Passwords. Это не число взломов ваших аккаунтов.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var resultSection: some View {
        switch viewModel.state {
        case .idle, .loading: EmptyView()
        case .failure(let error): ErrorSection(error: error)
        case .success(let count):
            Section("Результат проверки") {
                if count > 0 {
                    StatusCard(title: "Пароль найден в утечках",
                               detail: "Число появлений в базе: \(count.formatted(.number.locale(Locale(identifier: "ru_RU")))). Замените его везде, где использовали.",
                               symbol: "exclamationmark.shield", color: .red)
                    Button("Открыть план действий", action: showPlan)
                } else {
                    StatusCard(title: "Пароль не найден в базе",
                               detail: "Это не доказывает его надёжность. Используйте длинный уникальный пароль и двухфакторную защиту.",
                               symbol: "magnifyingglass", color: .blue)
                }
            }.privacySensitive()
        }
    }

    private func check() {
        isFocused = false
        viewModel.check()
    }
}

#Preview {
    NavigationStack {
        PasswordCheckView(viewModel: PasswordCheckViewModel(
            service: LivePasswordService(client: HIBPClient())), showPlan: {})
            .navigationTitle("Проверка пароля")
    }
}
