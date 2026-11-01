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
