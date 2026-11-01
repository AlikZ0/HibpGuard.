import SwiftUI

struct ActionPlanView: View {
    @ObservedObject var store: ActionPlanStore
    @State private var showReset = false

    var body: some View {
        List {
            Section {
                Text("Выполнено: \(store.completedIDs.count) из \(ActionStep.all.count)")
                    .font(.headline)
                Text("Общий список без привязки к аккаунту. Для новой утечки сбросьте отметки. Они сохраняются на этом устройстве.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("После обнаружения утечки") {
                ForEach(ActionStep.all) { step in
                    let completed = store.completedIDs.contains(step.id)
                    Button {
                        store.toggle(step.id)
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                                .font(.title2).foregroundStyle(completed ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(step.title).font(.headline).foregroundStyle(.primary)
                                Text(step.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(step.title + ". " + step.detail)
                    .accessibilityValue(completed ? "Выполнено" : "Не выполнено")
                    .accessibilityHint("Двойное нажатие меняет отметку")
                }
            }
            if let error = store.error {
                Section {
                    Text(error.message).foregroundStyle(.orange)
                    Button("Повторить чтение отметок") { store.reload() }
                }
            }
            Section {
                Button("Сбросить отметки", role: .destructive) { showReset = true }
                    .disabled(store.completedIDs.isEmpty)
            }
        }
        .confirmationDialog("Сбросить отметки плана?", isPresented: $showReset, titleVisibility: .visible) {
            Button("Сбросить", role: .destructive) { store.reset() }
        }
    }
}

#Preview {
    NavigationStack { ActionPlanView(store: ActionPlanStore()).navigationTitle("План действий") }
}
