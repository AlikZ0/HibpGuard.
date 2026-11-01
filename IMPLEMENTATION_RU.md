# HibpGuard: пошаговая реализация с полным кодом

Начните с [архитектуры и структуры папок](ARCHITECTURE_RU.md). Ниже файлы сгруппированы по порядку изучения: общий слой, email, пароль, план действий и настройки. Все файлы уже включены в готовый Xcode-проект. Вручную создавать пустое приложение для переноса кода не требуется.

Требования к запуску и ограничения проверки описаны в [README](README_RU.md).

## Шаг 1. Общая модель и сетевой слой

Создаём общий контракт состояний и ошибок. Транспорт отделён от логики HIBP: в тестах его заменяет actor, возвращающий подготовленный ответ. Модели не знают об интерфейсе. Для чтения этого шага откройте архитектуру: сначала рассматриваются слои, затем экраны.

### `HibpGuard/Models/CheckState.swift`

Один enum исключает одновременные состояния загрузки, успеха и ошибки.

```swift
import Foundation

enum CheckState<Value> {
    case idle
    case loading
    case success(Value)
    case failure(AppError)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
```

### `HibpGuard/Models/AppError.swift`

Ошибки имеют понятные сообщения без email в URL. RetryAfter принимает секунды и HTTP-date.

```swift
import Foundation

enum AppError: Error, Equatable, Sendable {
    case invalidEmail
    case emptyPassword
    case missingAPIKey
    case invalidAPIKey
    case forbidden
    case rateLimited(until: Date?)
    case timeout
    case network
    case invalidResponse
    case httpStatus(Int)
    case keychain(Int32)
    case storage
    case unexpected

    var message: String {
        switch self {
        case .invalidEmail:
            return "Введите email в формате name@example.com."
        case .emptyPassword:
            return "Введите пароль. Пробелы в пароле учитываются."
        case .missingAPIKey:
            return "Добавьте свой API-ключ HIBP в настройках или включите деморежим."
        case .invalidAPIKey:
            return "HIBP отклонил API-ключ (401). Проверьте ключ и подписку."
        case .forbidden:
            return "HIBP запретил запрос (403). Возможные причины: ограничения подписки, блокировка или отсутствие User-Agent. HibpGuard отправляет User-Agent."
        case .rateLimited(let until):
            guard let until else {
                return "Превышен лимит HIBP (429). Сервер не указал срок ожидания. Повторите запрос позже."
            }
            let seconds = max(0, Int(ceil(until.timeIntervalSinceNow)))
            if seconds == 0 { return "Ожидание после 429 завершилось. Можно повторить проверку." }
            return "Превышен лимит HIBP (429). Retry-After: ещё \(seconds) сек."
        case .timeout:
            return "Сервер не ответил вовремя. Проверьте соединение и повторите запрос."
        case .network:
            return "Не удалось подключиться к HIBP. Проверьте интернет."
        case .invalidResponse:
            return "Получен некорректный ответ. Результат проверки неизвестен. Повторите запрос позже."
        case .httpStatus(let code):
            return "Сервер вернул HTTP \(code). Результат проверки неизвестен."
        case .keychain(let status):
            return "Не удалось открыть Keychain (\(status)). Разблокируйте устройство и повторите действие."
        case .storage:
            return "Не удалось сохранить или прочитать отметки плана действий."
        case .unexpected:
            return "Не удалось завершить проверку. Повторите запрос."
        }
    }
}

enum RetryAfter {
    /// HIBP uses seconds; HTTP-date is also accepted for HTTP compatibility.
    static func deadline(header: String?, now: Date = Date()) -> Date? {
        guard let value = header?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        if let seconds = Double(value), seconds.isFinite, seconds >= 0,
           seconds <= 365 * 24 * 60 * 60 {
            return now.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return nil }
        return max(now, date)
    }
}
```

### `HibpGuard/Models/Breach.swift`

CodingKeys связывает Swift-имена с JSON HIBP. Дата утечки форматируется без смещения дня из-за часового пояса.

```swift
import Foundation

/// The full model is requested with truncateResponse=false.
struct Breach: Decodable, Identifiable, Equatable, Sendable {
    let name: String
    let title: String
    let breachDate: String
    let dataClasses: [String]
    let isVerified: Bool

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case title = "Title"
        case breachDate = "BreachDate"
        case dataClasses = "DataClasses"
        case isVerified = "IsVerified"
    }

    var formattedDate: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        parser.isLenient = false
        guard let date = parser.date(from: breachDate) else { return breachDate }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    static func localizedDataClass(_ value: String) -> String {
        let labels = [
            "Email addresses": "Email-адреса",
            "Passwords": "Пароли",
            "Password hints": "Подсказки к паролям",
            "Usernames": "Имена пользователей",
            "Names": "Имена",
            "Phone numbers": "Телефонные номера",
            "IP addresses": "IP-адреса",
            "Physical addresses": "Почтовые адреса",
            "Dates of birth": "Даты рождения",
            "Credit cards": "Данные банковских карт"
        ]
        // New HIBP data classes remain visible even before a translation is added.
        return labels[value] ?? value
    }
}
```

### `HibpGuard/Networking/HTTPTransport.swift`

Ephemeral URLSession ограничивает локальное сохранение сетевых данных. Делегат останавливает редиректы.

```swift
import Foundation

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// A redirect is never followed: a custom API-key header must stay on its host.
private final class RejectRedirectsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration,
                             delegate: RejectRedirectsDelegate(), delegateQueue: nil)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.invalidResponse }
        return (data, http)
    }
}
```

### `HibpGuard/Networking/PasswordFingerprint.swift`

CryptoKit вычисляет SHA-1 на устройстве. Пароль не обрезается, не меняет регистр и не нормализуется.

```swift
import Foundation
import CryptoKit

struct PasswordFingerprint: Equatable, Sendable {
    let prefix: String
    let suffix: String

    init(password: String) {
        // SHA-1 is required by Pwned Passwords; it is NOT used for password storage.
        // Do not trim, lowercase or Unicode-normalize a password.
        let digest = Insecure.SHA1.hash(data: Data(password.utf8))
        let hex = digest.map { String(format: "%02X", $0) }.joined()
        prefix = String(hex.prefix(5))
        suffix = String(hex.dropFirst(5))
    }
}
```

### `HibpGuard/Networking/PasswordRangeParser.swift`

Строгий парсер отделяет настоящий нулевой результат от повреждённого ответа. Padding с нулевым счётчиком не считается утечкой.

```swift
import Foundation

enum PasswordRangeParser {
    static func occurrences(of expectedSuffix: String, in data: Data) throws -> Int {
        guard expectedSuffix.count == 35, isHex(expectedSuffix),
              let body = String(data: data, encoding: .utf8) else {
            throw AppError.invalidResponse
        }
        let lines = body.split(whereSeparator: { $0.isNewline })
        guard !lines.isEmpty else { throw AppError.invalidResponse }
        var match: Int?
        for line in lines {
            let fields = line.split(separator: ":", omittingEmptySubsequences: false)
            guard fields.count == 2, fields[0].count == 35,
                  isHex(fields[0]), !fields[1].isEmpty,
                  fields[1].utf8.allSatisfy({ (48...57).contains($0) }),
                  let count = Int(fields[1]) else {
                // An HTML error page must never be interpreted as "not found".
                throw AppError.invalidResponse
            }
            if fields[0].uppercased() == expectedSuffix.uppercased() {
                guard match == nil else { throw AppError.invalidResponse }
                match = count
            }
            // Add-Padding rows have count 0 and do not indicate a breach.
        }
        return match ?? 0
    }

    private static func isHex<S: StringProtocol>(_ value: S) -> Bool {
        value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }
}
```

### `HibpGuard/Networking/HIBPClient.swift`

Клиент строит два вида запросов. Ключ прикрепляется только к email-запросу, а password URL содержит только префикс.

```swift
import Foundation

struct HIBPClient: Sendable {
    private let transport: any HTTPTransport
    private let userAgent = "HibpGuard/1.0 (iOS)"

    init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    func breaches(for email: String, apiKey: String) async throws -> [Breach] {
        // Encode the whole email as ONE path component, including +, /, ? and #.
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let encoded = email.addingPercentEncoding(withAllowedCharacters: safe) else {
            throw AppError.invalidEmail
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "haveibeenpwned.com"
        components.percentEncodedPath = "/api/v3/breachedaccount/" + encoded
        components.queryItems = [URLQueryItem(name: "truncateResponse", value: "false")]
        guard let url = components.url else { throw AppError.invalidEmail }
        var request = makeRequest(url: url, accept: "application/json")
        request.setValue(apiKey, forHTTPHeaderField: "hibp-api-key")
        let (data, response) = try await send(request)
        if response.statusCode == 404 { return [] }
        try validate(response)
        do {
            return try JSONDecoder().decode([Breach].self, from: data)
                .sorted { $0.breachDate > $1.breachDate }
        } catch {
            throw AppError.invalidResponse
        }
    }

    func passwordOccurrences(for fingerprint: PasswordFingerprint) async throws -> Int {
        // Only this 5-character prefix crosses the network boundary.
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.pwnedpasswords.com"
        components.path = "/range/" + fingerprint.prefix
        guard let url = components.url else { throw AppError.invalidResponse }
        var request = makeRequest(url: url, accept: "text/plain")
        request.setValue("true", forHTTPHeaderField: "Add-Padding")
        let (data, response) = try await send(request)
        // Every valid password range returns 200, so 404 here is an error.
        try validate(response)
        return try PasswordRangeParser.occurrences(of: fingerprint.suffix, in: data)
    }

    private func makeRequest(url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let result = try await transport.data(for: request)
            try Task.checkCancellation()
            guard result.0.count <= 2 * 1024 * 1024 else { throw AppError.invalidResponse }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw AppError.timeout
            default: throw AppError.network
            }
        } catch let error as AppError {
            throw error
        } catch {
            // Do not surface URLSession descriptions: they can contain the email URL.
            throw AppError.network
        }
    }

    private func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200: return
        case 400: throw AppError.httpStatus(400)
        case 401: throw AppError.invalidAPIKey
        case 403: throw AppError.forbidden
        case 429:
            throw AppError.rateLimited(until: RetryAfter.deadline(
                header: response.value(forHTTPHeaderField: "Retry-After")))
        default: throw AppError.httpStatus(response.statusCode)
        }
    }
}
```

### `HibpGuard/Views/SharedViews.swift`

Общие карточки, ошибки и ссылка на источник данных поддерживают одинаковые подписи на экранах.

```swift
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
```

Проверка этого шага: NetworkingTests и PasswordPrivacyTests ниже проверяют контракт запросов и локальное сопоставление. До подключения всех файлов удобнее пользоваться уже собранной структурой исходников из архива.

## Шаг 2. Экран email

Ключ поступает из Keychain через сервис. ViewModel управляет выбранным режимом, проверяет ввод и публикует состояние. Экран показывает список утечек или пустой результат. Демо никогда не выдаётся за настоящую проверку.

### `HibpGuard/Storage/KeychainAPIKeyStore.swift`

Ключ хранится с доступностью WhenUnlockedThisDeviceOnly. При замене сначала выполняется update; старое значение не удаляется заранее.

```swift
import Foundation
import Security

protocol APIKeyStoring: Sendable {
    func readAPIKey() throws -> String?
    func saveAPIKey(_ key: String) throws
    func deleteAPIKey() throws
}

struct KeychainAPIKeyStore: APIKeyStoring {
    private let service: String
    private let account = "hibp-api-key"

    init(service: String = (Bundle.main.bundleIdentifier ?? "HibpGuard") + ".hibp") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func readAPIKey() throws -> String? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AppError.keychain(status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw AppError.keychain(errSecDecode)
        }
        return key
    }

    func saveAPIKey(_ key: String) throws {
        let updates: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        // Update first: a failed replacement must not delete an existing key.
        let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            let attributes = query.merging(updates) { _, new in new }
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw AppError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw AppError.keychain(status)
        }
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.keychain(status)
        }
    }
}
```

### `HibpGuard/Networking/CheckServices.swift`

Протоколы позволяют подключить реальный и демонстрационный сервис. Проверка пароля использует отдельный сервис без доступа к Keychain.

```swift
import Foundation

protocol EmailChecking: Sendable {
    func breaches(for email: String) async throws -> [Breach]
}

protocol PasswordChecking: Sendable {
    func occurrences(for fingerprint: PasswordFingerprint) async throws -> Int
}

struct LiveEmailService: EmailChecking {
    let client: HIBPClient
    let keyStore: any APIKeyStoring

    func breaches(for email: String) async throws -> [Breach] {
        guard let key = try keyStore.readAPIKey(), !key.isEmpty else {
            throw AppError.missingAPIKey
        }
        return try await client.breaches(for: email, apiKey: key)
    }
}

struct LivePasswordService: PasswordChecking {
    let client: HIBPClient

    func occurrences(for fingerprint: PasswordFingerprint) async throws -> Int {
        try await client.passwordOccurrences(for: fingerprint)
    }
}

/// Never calls a server. The screen explicitly labels all results as demo data.
struct MockEmailService: EmailChecking {
    func breaches(for email: String) async throws -> [Breach] {
        try Task.checkCancellation()
        if email.lowercased() == "clean@example.com" { return [] }
        return [Breach(name: "DemoService", title: "Пример сервиса (демо)",
                       breachDate: "2025-04-18", dataClasses: ["Email addresses", "Passwords"],
                       isVerified: true)]
    }
}
```

### `HibpGuard/ViewModels/EmailCheckViewModel.swift`

Изменение адреса или режима сбрасывает результат и отменяет старую задачу. Серверный срок ожидания сохраняется независимо от ввода.

```swift
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
```

### `HibpGuard/Views/EmailCheckView.swift`

SwiftUI отображает состояние модели. TimelineView обновляет срок ожидания без отдельного постоянно работающего таймера во ViewModel.

```swift
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
```

Ручная проверка: в Демо введите example@example.com, затем clean@example.com. Переключитесь на HIBP API без ключа и убедитесь, что появляется предложение добавить ключ. Для настоящего тестового запроса используйте официальный пример из README.

## Шаг 3. Экран пароля

На главном акторе вычисляем небольшой fingerprint и очищаем поле. Асинхронная задача получает fingerprint, а не пароль. Серверный ответ сравнивается локально. В интерфейс возвращается только число появлений в базе.

### `HibpGuard/ViewModels/PasswordCheckViewModel.swift`

Идентификатор задачи защищает экран от устаревшего ответа даже при сервисе, который игнорирует отмену.

```swift
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
```

### `HibpGuard/Views/PasswordCheckView.swift`

SecureField скрывает ввод. Нулевой результат подписан как отсутствие совпадения, без вывода о стойкости пароля.

```swift
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
```

Ручная проверка: password должен дать ненулевой счётчик. При отключённом интернете должна появиться ошибка подключения. Изменение ввода после результата очищает его; уход на другую вкладку отменяет password-проверку.

## Шаг 4. Интерактивный план действий

Сохраняем только стабильные ID действий в небольшом JSON. Это общий план на устройстве: аккаунты и пароли в него не записываются. Store одновременно публикует состояние для этого простого экрана и управляет сохранением.

### `HibpGuard/Models/ActionStep.swift`

У действий есть постоянные ID: изменение формулировки не ломает сохранённые отметки.

```swift
import Foundation

struct ActionStep: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String

    static let all: [ActionStep] = [
        .init(id: "change-password", title: "Сменить пароль",
              detail: "Откройте официальный сайт или приложение сервиса. Задайте новый уникальный пароль и завершите другие сеансы."),
        .init(id: "enable-2fa", title: "Включить двухфакторную защиту",
              detail: "Используйте passkey или приложение-аутентификатор, если сервис их поддерживает. Сохраните резервные коды."),
        .init(id: "reused-passwords", title: "Проверить повторно использованные пароли",
              detail: "Замените этот пароль во всех аккаунтах, где он повторялся. Начните с почты и финансовых сервисов."),
        .init(id: "devices", title: "Проверить устройства и активные сеансы",
              detail: "Обновите систему и приложения. Удалите неизвестные расширения, проверьте устройства и список входов в аккаунт.")
    ]
}
```

### `HibpGuard/Storage/ActionPlanStore.swift`

Запись атомарна и использует полную файловую защиту iOS. UI подтверждает отметку только после успешной записи.

```swift
import Foundation
import Combine

protocol ChecklistStorage {
    func load() throws -> Set<String>
    func save(_ completedIDs: Set<String>) throws
}

struct FileChecklistStorage: ChecklistStorage {
    let url: URL

    init(url: URL) { self.url = url }

    init() throws {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent("HibpGuard", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("action-plan.json")
    }

    func load() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return Set(try JSONDecoder().decode([String].self, from: Data(contentsOf: url)))
    }

    func save(_ completedIDs: Set<String>) throws {
        let data = try JSONEncoder().encode(completedIDs.sorted())
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}

@MainActor
final class ActionPlanStore: ObservableObject {
    @Published private(set) var completedIDs: Set<String> = []
    @Published private(set) var error: AppError?
    private let storage: (any ChecklistStorage)?

    init(storage: any ChecklistStorage) {
        self.storage = storage
        reload()
    }

    init() {
        do {
            storage = try FileChecklistStorage()
        } catch {
            storage = nil
            self.error = .storage
        }
        reload()
    }

    func reload() {
        guard let storage else { error = .storage; return }
        do {
            let knownIDs = Set(ActionStep.all.map(\.id))
            completedIDs = try storage.load().intersection(knownIDs)
            error = nil
        } catch {
            self.error = .storage
        }
    }

    func toggle(_ id: String) {
        guard ActionStep.all.contains(where: { $0.id == id }) else { return }
        var next = completedIDs
        if !next.insert(id).inserted { next.remove(id) }
        persist(next)
    }

    func reset() { persist([]) }

    private func persist(_ next: Set<String>) {
        guard let storage else { error = .storage; return }
        do {
            try storage.save(next)
            // Change UI only after a successful write.
            completedIDs = next
            error = nil
        } catch {
            self.error = .storage
        }
    }
}
```

### `HibpGuard/Views/ActionPlanView.swift`

Кнопки меняют отметки и сообщают их состояние VoiceOver. Сброс требует подтверждения внутри приложения.

```swift
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
```

Ручная проверка: отметьте два пункта и перезапустите приложение. Они должны остаться отмеченными. После сброса список пустой. Ошибка записи проверяется отдельным тестом хранилища.

## Шаг 5. Настройки ключа

Сохранённый ключ не подставляется обратно в поле. Экран показывает наличие записи, принимает замену и позволяет удалить ключ. Проверка формата не означает, что подписка действительна.

### `HibpGuard/ViewModels/SettingsViewModel.swift`

ViewModel различает успешное сохранение и ошибку Keychain. Черновик очищается после сохранения и при уходе в фон.

```swift
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
```

### `HibpGuard/Views/SettingsView.swift`

Отдельный SecureField и явное удаление дают пользователю управление личным ключом.

```swift
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
```

Ручная проверка: некорректный формат отклоняется локально. После сохранения корректного по форме ключа поле пустое и виден статус. Его действительность проверяется реальным email-запросом.

## Шаг 6. Собираем приложение

Создаём зависимости в одном месте. AppContainer связывает сервисы, хранилища и ViewModel. RootView содержит вкладки, переход к плану и очистку чувствительного состояния.

### `HibpGuard/App/AppContainer.swift`

Единственное место сборки зависимостей упрощает последующую замену сервиса или транспорта.

```swift
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
```

### `HibpGuard/App/RootView.swift`

TabView переключает три сценария. ScenePhase отменяет запросы и очищает ввод, когда приложение перестаёт быть активным.

```swift
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
```

### `HibpGuard/App/HibpGuardApp.swift`

StateObject удерживает контейнер на время жизни приложения.

```swift
import SwiftUI

@main
@MainActor
struct HibpGuardApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup { RootView(container: container) }
    }
}
```

Откройте готовый HibpGuard.xcodeproj, выберите iPhone simulator и нажмите Run. Проверьте светлую и тёмную темы, крупный текст, возврат из фона и переход к плану действий.

## Шаг 7. Тесты

Все сетевые тесты используют подготовленные ответы. Тесты не требуют платного ключа, не отправляют реальные пароли и не расходуют лимит HIBP. Keychain-тест работает с отдельной временной записью.

### `HibpGuardTests/PasswordPrivacyTests.swift`

Проверяем известный хэш, точные байты пароля, padding и отказ от ложного нулевого результата.

```swift
import XCTest
@testable import HibpGuard

final class PasswordPrivacyTests: XCTestCase {
    func testKnownSHA1Vector() {
        let value = PasswordFingerprint(password: "password")
        XCTAssertEqual(value.prefix, "5BAA6")
        XCTAssertEqual(value.suffix, "1E4C9B93F3F0682250B6CF8331B7EE68FD8")
        XCTAssertEqual(value.prefix.count, 5)
        XCTAssertEqual(value.suffix.count, 35)
    }

    func testPasswordIsNotTrimmedOrNormalized() {
        XCTAssertNotEqual(PasswordFingerprint(password: " password "), PasswordFingerprint(password: "password"))
        XCTAssertNotEqual(PasswordFingerprint(password: "PASSWORD"), PasswordFingerprint(password: "password"))
        XCTAssertNotEqual(PasswordFingerprint(password: "\u{00E9}"), PasswordFingerprint(password: "e\u{0301}"))
    }

    func testCRLFParsingAndPadding() throws {
        let target = PasswordFingerprint(password: "password").suffix
        let padding = String(repeating: "0", count: 35)
        let body = "\(padding):0\r\n\(target):12345\r\n"
        XCTAssertEqual(try PasswordRangeParser.occurrences(of: target, in: Data(body.utf8)), 12345)
        XCTAssertEqual(try PasswordRangeParser.occurrences(of: padding, in: Data(body.utf8)), 0)
    }

    func testAbsentSuffixIsZeroOnlyForValidResponse() throws {
        let target = PasswordFingerprint(password: "password").suffix
        let other = String(repeating: "A", count: 35)
        XCTAssertEqual(try PasswordRangeParser.occurrences(of: target, in: Data("\(other):15\n".utf8)), 0)
    }

    func testMalformedResponsesNeverLookLikeCleanPasswords() {
        let target = PasswordFingerprint(password: "password").suffix
        let invalid = ["", "<html>Service unavailable</html>", "\(target):-1\n",
                       "NOT-A-HASH:12\n", "\(target):9999999999999999999999999\n",
                       "\(target):1:2\n", "\(target):1\n\(target):2\n",
                       "\(target):1\nBAD-ROW\n"]
        for body in invalid {
            XCTAssertThrowsError(try PasswordRangeParser.occurrences(of: target, in: Data(body.utf8))) {
                XCTAssertEqual($0 as? AppError, .invalidResponse)
            }
        }
    }
}
```

### `HibpGuardTests/NetworkingTests.swift`

Проверяем URL, заголовки и разницу между статусами двух API.

```swift
import XCTest
@testable import HibpGuard

actor RecordingTransport: HTTPTransport {
    private let status: Int
    private let body: Data
    private let headers: [String: String]
    private(set) var lastRequest: URLRequest?

    init(status: Int = 200, body: String = "", headers: [String: String] = [:]) {
        self.status = status
        self.body = Data(body.utf8)
        self.headers = headers
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status,
                                             httpVersion: "HTTP/1.1", headerFields: headers) else {
            throw AppError.invalidResponse
        }
        return (body, response)
    }
}

private struct FailingTransport: HTTPTransport {
    let code: URLError.Code
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(code)
    }
}

final class NetworkingTests: XCTestCase {
    func testEmailRequestsFullModelAndEncodesReservedCharacters() async throws {
        let body = """
        [{"Name":"Example","Title":"Example service","BreachDate":"2025-01-02",
          "DataClasses":["Passwords"],"IsVerified":true}]
        """
        let transport = RecordingTransport(body: body)
        let client = HIBPClient(transport: transport)
        let result = try await client.breaches(for: "a+b/?#%@example.com", apiKey: "example-key")
        XCTAssertEqual(result.first?.dataClasses, ["Passwords"])
        XCTAssertEqual(result.first?.breachDate, "2025-01-02")
        let captured = await transport.lastRequest
        let request = try XCTUnwrap(captured)
        let url = try XCTUnwrap(request.url)
        XCTAssertTrue(url.absoluteString.contains("a%2Bb%2F%3F%23%25%40example.com"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "truncateResponse", value: "false")])
        XCTAssertEqual(request.value(forHTTPHeaderField: "hibp-api-key"), "example-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "HibpGuard/1.0 (iOS)")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testEmail404MeansNoMatches() async throws {
        let client = HIBPClient(transport: RecordingTransport(status: 404))
        let result = try await client.breaches(for: "example@example.com", apiKey: "example-key")
        XCTAssertTrue(result.isEmpty)
    }

    func testPasswordRequestContainsOnlyPrefixAndEnablesPadding() async throws {
        let fingerprint = PasswordFingerprint(password: "password")
        let transport = RecordingTransport(body: "\(fingerprint.suffix):123\r\n")
        let client = HIBPClient(transport: transport)
        let count = try await client.passwordOccurrences(for: fingerprint)
        XCTAssertEqual(count, 123)
        let captured = await transport.lastRequest
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://api.pwnedpasswords.com/range/5BAA6")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "hibp-api-key"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Add-Padding"), "true")
        XCTAssertFalse(request.url?.absoluteString.contains(fingerprint.suffix) ?? true)
        XCTAssertFalse(request.url?.absoluteString.contains("password/") ?? true)
    }

    func testPassword404IsAnError() async {
        let client = HIBPClient(transport: RecordingTransport(status: 404))
        do {
            _ = try await client.passwordOccurrences(for: PasswordFingerprint(password: "password"))
            XCTFail("A range API error must not produce a clean result")
        } catch { XCTAssertEqual(error as? AppError, .httpStatus(404)) }
    }

    func testAuthorizationAndServiceErrorsStayErrors() async {
        let cases: [(Int, AppError)] = [(401, .invalidAPIKey), (403, .forbidden), (503, .httpStatus(503))]
        for (status, expected) in cases {
            let client = HIBPClient(transport: RecordingTransport(status: status))
            do {
                _ = try await client.breaches(for: "example@example.com", apiKey: "example-key")
                XCTFail("Expected HTTP error")
            } catch { XCTAssertEqual(error as? AppError, expected) }
        }
    }

    func test429CarriesRetryAfter() async {
        let transport = RecordingTransport(status: 429, headers: ["Retry-After": "60"])
        let client = HIBPClient(transport: transport)
        do {
            _ = try await client.breaches(for: "example@example.com", apiKey: "example-key")
            XCTFail("Expected rate limit")
        } catch let AppError.rateLimited(until) {
            XCTAssertNotNil(until)
            XCTAssertEqual(until?.timeIntervalSinceNow ?? 0, 60, accuracy: 2)
        } catch { XCTFail("Unexpected error type") }
    }

    func testInvalidJSONDoesNotProduceCleanEmailResult() async {
        let client = HIBPClient(transport: RecordingTransport(body: "[{\"Name\":\"OnlyTruncatedName\"}]"))
        do {
            _ = try await client.breaches(for: "example@example.com", apiKey: "example-key")
            XCTFail("Missing full-model fields must fail decoding")
        } catch { XCTAssertEqual(error as? AppError, .invalidResponse) }
    }

    func testTimeoutHasSafeUserMessage() async {
        let client = HIBPClient(transport: FailingTransport(code: .timedOut))
        do {
            _ = try await client.breaches(for: "private@example.com", apiKey: "example-key")
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? AppError, .timeout)
            XCTAssertFalse((error as? AppError)?.message.contains("private@example.com") ?? true)
        }
    }

    func testCancellationIsPreserved() async {
        let client = HIBPClient(transport: FailingTransport(code: .cancelled))
        do {
            _ = try await client.passwordOccurrences(for: PasswordFingerprint(password: "password"))
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testRetryAfterFormats() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(RetryAfter.deadline(header: "42", now: now), now.addingTimeInterval(42))
        XCTAssertEqual(RetryAfter.deadline(header: "Thu, 01 Jan 1970 00:20:00 GMT", now: now),
                       Date(timeIntervalSince1970: 1_200))
        XCTAssertEqual(RetryAfter.deadline(header: "Thu, 01 Jan 1970 00:00:00 GMT", now: now), now)
        for header in [nil, "", "-2", "NaN", "inf", "not-a-date"] as [String?] {
            XCTAssertNil(RetryAfter.deadline(header: header, now: now))
        }
    }
}
```

### `HibpGuardTests/ViewModelTests.swift`

Проверяем отмену и запоздалые ответы через управляемый actor-сервис.

```swift
import XCTest
@testable import HibpGuard

private struct FixedPasswordService: PasswordChecking {
    let result: Int
    func occurrences(for fingerprint: PasswordFingerprint) async throws -> Int { result }
}

private struct BrokenPasswordService: PasswordChecking {
    func occurrences(for fingerprint: PasswordFingerprint) async throws -> Int { throw AppError.network }
}

/// Intentionally ignores cancellation: the view model must reject late results.
private actor GatedPasswordService: PasswordChecking {
    private var answer: CheckedContinuation<Int, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func occurrences(for fingerprint: PasswordFingerprint) async throws -> Int {
        await withCheckedContinuation { continuation in
            answer = continuation
            startWaiters.forEach { $0.resume() }
            startWaiters = []
        }
    }

    func waitUntilStarted() async {
        if answer != nil { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish(count: Int) {
        answer?.resume(returning: count)
        answer = nil
    }
}

final class ViewModelTests: XCTestCase {
    @MainActor
    func testPasswordFieldClearsBeforeRequestCompletes() async {
        let service = GatedPasswordService()
        let model = PasswordCheckViewModel(service: service)
        model.password = "password"
        let task = model.check()
        XCTAssertEqual(model.password, "")
        XCTAssertTrue(model.state.isLoading)
        await service.waitUntilStarted()
        await service.finish(count: 123)
        await task?.value
        guard case .success(let count) = model.state else { return XCTFail("Expected result") }
        XCTAssertEqual(count, 123)
    }

    @MainActor
    func testOldResultCannotOverwriteChangedInput() async {
        let service = GatedPasswordService()
        let model = PasswordCheckViewModel(service: service)
        model.password = "password"
        let task = model.check()
        await service.waitUntilStarted()
        model.password = "new input"
        await service.finish(count: 999)
        await task?.value
        guard case .idle = model.state else { return XCTFail("Stale result was published") }
    }

    @MainActor
    func testBackgroundClearingCancelsPendingResult() async {
        let service = GatedPasswordService()
        let model = PasswordCheckViewModel(service: service)
        model.password = "password"
        let task = model.check()
        await service.waitUntilStarted()
        model.clearSensitiveState()
        await service.finish(count: 999)
        await task?.value
        XCTAssertEqual(model.password, "")
        guard case .idle = model.state else { return XCTFail("Background result was published") }
    }

    @MainActor
    func testNetworkFailureNeverBecomesZero() async {
        let model = PasswordCheckViewModel(service: BrokenPasswordService())
        model.password = "password"
        await model.check()?.value
        guard case .failure(let error) = model.state else { return XCTFail("Expected failure") }
        XCTAssertEqual(error, .network)
    }

    @MainActor
    func testEmptyPasswordDoesNotStartRequest() {
        let model = PasswordCheckViewModel(service: FixedPasswordService(result: 1))
        XCTAssertNil(model.check())
        guard case .failure(let error) = model.state else { return XCTFail("Expected input error") }
        XCTAssertEqual(error, .emptyPassword)
    }

    @MainActor
    func testChangingDemoModeInvalidatesDisplayedResult() async {
        let model = EmailCheckViewModel(live: MockEmailService())
        model.email = "example@example.com"
        await model.check()?.value
        guard case .success = model.state else { return XCTFail("Expected demo result") }
        model.useDemo = false
        guard case .idle = model.state else { return XCTFail("Demo result remained visible in live mode") }
    }

    @MainActor
    func testInvalidEmailIsRejected() {
        let model = EmailCheckViewModel(live: MockEmailService())
        model.email = "not-an-email"
        XCTAssertNil(model.check())
        guard case .failure(let error) = model.state else { return XCTFail("Expected input error") }
        XCTAssertEqual(error, .invalidEmail)
    }
}
```

### `HibpGuardTests/StorageTests.swift`

Проверяем Keychain и сохранение отметок, включая неудачную запись.

```swift
import XCTest
import Security
@testable import HibpGuard

private final class MemoryChecklistStorage: ChecklistStorage {
    var value: Set<String> = []
    var failsSaving = false
    func load() throws -> Set<String> { value }
    func save(_ completedIDs: Set<String>) throws {
        if failsSaving { throw AppError.storage }
        value = completedIDs
    }
}

final class StorageTests: XCTestCase {
    func testKeychainRoundTripAndAccessibility() throws {
        let service = "HibpGuardTests." + UUID().uuidString
        let store = KeychainAPIKeyStore(service: service)
        defer { try? store.deleteAPIKey() }
        XCTAssertNil(try store.readAPIKey())
        try store.saveAPIKey(String(repeating: "a", count: 32))
        XCTAssertEqual(try store.readAPIKey(), String(repeating: "a", count: 32))
        try store.saveAPIKey(String(repeating: "b", count: 32))
        XCTAssertEqual(try store.readAPIKey(), String(repeating: "b", count: 32))
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: "hibp-api-key",
                                    kSecReturnAttributes as String: true]
        var item: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &item), errSecSuccess)
        let attributes = try XCTUnwrap(item as? [String: Any])
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        try store.deleteAPIKey()
        XCTAssertNil(try store.readAPIKey())
    }

    func testChecklistFileRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FileChecklistStorage(url: directory.appendingPathComponent("checklist.json"))
        XCTAssertTrue(try storage.load().isEmpty)
        try storage.save(["devices", "enable-2fa"])
        XCTAssertEqual(try storage.load(), ["devices", "enable-2fa"])
    }

    @MainActor
    func testChecklistSurvivesRecreatingStore() {
        let storage = MemoryChecklistStorage()
        let first = ActionPlanStore(storage: storage)
        first.toggle("devices")
        let reopened = ActionPlanStore(storage: storage)
        XCTAssertTrue(reopened.completedIDs.contains("devices"))
    }

    @MainActor
    func testFailedWriteDoesNotShowUnsavedCheckmark() {
        let storage = MemoryChecklistStorage()
        storage.failsSaving = true
        let model = ActionPlanStore(storage: storage)
        model.toggle("devices")
        XCTAssertFalse(model.completedIDs.contains("devices"))
        XCTAssertEqual(model.error, .storage)
    }

    @MainActor
    func testUnknownActionIDsAreIgnored() {
        let storage = MemoryChecklistStorage()
        storage.value = ["devices", "removed-action"]
        let model = ActionPlanStore(storage: storage)
        XCTAssertEqual(model.completedIDs, ["devices"])
    }
}
```

На Mac нажмите ⌘U или выполните bash Tools/test_on_simulator.sh. Тесты добавлены в исходники, но в среде подготовки не запускались: Xcode здесь отсутствует.

## Шаг 8. Проверка без локального Mac

Workflow запускается вручную на GitHub. Он собирает проект и запускает XCTest в симуляторе macOS runner. Подпись для установки на iPhone и сборка IPA в него не входят. Порядок загрузки репозитория описан в README.

### `Tools/test_on_simulator.sh`

Выбираем доступный iPhone-симулятор по UUID, чтобы не привязывать команду к конкретному названию модели.

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# A concrete simulator UUID is selected from the installed runtimes.
xcodebuild -version
hibp_simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime, entries in sorted(devices.items(), reverse=True):
    if "iOS" not in runtime:
        continue
    for device in entries:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            print(device["udid"])
            sys.exit(0)
sys.exit("No available iPhone simulator. Install an iOS runtime in Xcode Settings > Components.")
')"

xcodebuild test \
  -project HibpGuard.xcodeproj \
  -scheme HibpGuard \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${hibp_simulator_id}" \
  -derivedDataPath build/DerivedData \
  -resultBundlePath "build/Tests-$(date -u +%Y%m%dT%H%M%SZ).xcresult"
```

### `.github/workflows/ios-check.yml`

Права токена ограничены чтением. Apple ID и API-ключи этому workflow не нужны.

```yaml
name: iOS simulator checks

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  test:
    runs-on: macos-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v6
        with:
          persist-credentials: false
      - name: Build and run XCTest on an installed iPhone simulator
        run: bash Tools/test_on_simulator.sh
```
