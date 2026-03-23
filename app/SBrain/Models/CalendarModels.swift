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
    let htmlLink: String?
    let status: String?

    // is_all_day는 백엔드에서 반환하지 않으므로 start 길이로 판단
    var isAllDay: Bool {
        start.count <= 10  // "2026-03-23" = date only = all day
    }

    enum CodingKeys: String, CodingKey {
        case id, title, start, end, description, location, attendees, status
        case htmlLink = "html_link"
    }
}
