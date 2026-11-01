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
