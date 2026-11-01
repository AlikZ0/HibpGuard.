import SwiftUI

struct StatusCard: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(color)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct HIBPAttribution: View {
    var body: some View {
        // Attribution is required for breach data and welcomed for password data.
        Link("Источник данных: Have I Been Pwned", destination: URL(string: "https://haveibeenpwned.com")!)
            .font(.footnote)
    }
}

struct ErrorSection: View {
    let error: AppError

    var body: some View {
        Section {
            StatusCard(title: "Проверка не завершена", detail: error.message,
                       symbol: "exclamationmark.triangle", color: .orange)
        }
        .accessibilityAddTraits(.updatesFrequently)
    }
}
