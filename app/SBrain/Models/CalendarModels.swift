import Foundation

// MARK: - Calendar Models

struct CalendarEvent: Identifiable, Codable {
    let id: String
    let title: String
    let start: String
    let end: String
    let description: String?
    let location: String?
    let attendees: [String]?
    let isAllDay: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, start, end, description, location, attendees
        case isAllDay = "is_all_day"
    }
}
