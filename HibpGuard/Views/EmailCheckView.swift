import SwiftUI

struct EmailCheckView: View {
    @ObservedObject var viewModel: EmailCheckViewModel
    let showPlan: () -> Void
    let showSettings: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        // TimelineView updates the Retry-After text and the disabled state.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Form {
                Section {
                    Picker("Режим проверки", selection: $viewModel.useDemo) {
                        Text("Демо").tag(true)
                        Text("HIBP API").tag(false)
                    }.pickerStyle(.segmented)
                    if viewModel.useDemo {
                        Label("Демонстрационные данные", systemImage: "testtube.2")
                            .font(.headline).foregroundStyle(.orange)
                        Text("Запросов в сеть нет. Любой корректный адрес покажет пример утечки; clean@example.com покажет пустой результат.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Email целиком отправляется в Have I Been Pwned по HTTPS. Для этого нужен ваш платный API-ключ.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Настроить API-ключ", action: showSettings)
                    }
                }

                Section("Email") {
                    TextField("name@example.com", text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .submitLabel(.search)
                        .onSubmit { check() }
                        .privacySensitive()
                        .disabled(viewModel.state.isLoading)
                        .accessibilityLabel("Email для проверки утечек")
                    Button(action: check) {
                        HStack {
                            if viewModel.state.isLoading { ProgressView() }
                            Text(viewModel.state.isLoading ? "Проверяем…" : "Проверить email")
                        }.frame(maxWidth: .infinity)
                    }
                    .disabled(!viewModel.canCheck(at: context.date))
                    if !viewModel.useDemo, let until = viewModel.retryNotBefore, until > context.date {
                        Text("Повторить можно через \(Int(ceil(until.timeIntervalSince(context.date)))) сек. (Retry-After)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if viewModel.state.isLoading {
                        Button("Отменить", role: .cancel) { viewModel.invalidate() }
                    }
                }

                resultSection

                Section {
                    HIBPAttribution()
                    Text("Отсутствие результатов означает только, что адрес не найден в доступных данных HIBP. Некоторые утечки не входят в публичный API.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var resultSection: some View {
        switch viewModel.state {
        case .idle, .loading:
            EmptyView()
        case .failure(let error):
            ErrorSection(error: error)
        case .success(let breaches):
            Section(viewModel.useDemo ? "Результат демонстрации" : "Результат проверки") {
                if breaches.isEmpty {
                    StatusCard(title: viewModel.useDemo ? "Пустой деморезультат" : "Совпадений не найдено",
                               detail: viewModel.useDemo ? "Это пример интерфейса, ваш адрес не проверялся."
                                    : "В доступной базе HIBP нет результатов для этого email.",
                               symbol: "magnifyingglass", color: .blue)
                } else {
                    StatusCard(title: viewModel.useDemo ? "Пример обнаруженной утечки" : "Найдено утечек: \(breaches.count)",
                               detail: viewModel.useDemo ? "Эти данные вымышлены. Для реального запроса выберите HIBP API."
                                    : "Проверьте, какие данные раскрыты, и выполните план действий.",
                               symbol: "exclamationmark.shield", color: .orange)
                    ForEach(breaches) { breach in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(breach.title).font(.headline)
                            Text("Дата утечки: \(breach.formattedDate)").font(.subheadline)
                            Text(breach.dataClasses.map(Breach.localizedDataClass).joined(separator: ", "))
                                .font(.subheadline).foregroundStyle(.secondary)
                            if !breach.isVerified {
                                Label("Данные об утечке не подтверждены HIBP", systemImage: "questionmark.circle")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }.padding(.vertical, 5)
                    }
                    Button("Открыть план действий", action: showPlan)
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
        EmailCheckView(viewModel: EmailCheckViewModel(live: MockEmailService()),
                       showPlan: {}, showSettings: {})
            .navigationTitle("Проверка email")
    }
}
