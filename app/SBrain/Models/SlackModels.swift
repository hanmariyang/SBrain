import Foundation

// MARK: - Slack Models

struct SlackMessage: Identifiable, Codable {
    let id: String
    let channel: String
    let channelName: String
    let user: String
    let userName: String
    let text: String
    let timestamp: String
    let threadTs: String?
    let urgency: String?           // high, medium, low
    let actionType: String?        // reply, calendar, both, none
    let summary: String?
    let draftReply: String?
    let calendarEvent: CalendarEventSuggestion?

    enum CodingKeys: String, CodingKey {
        case id, channel, user, text, timestamp, urgency, summary
        case channelName = "channel_name"
        case userName = "user_name"
        case threadTs = "thread_ts"
        case actionType = "action_type"
        case draftReply = "draft_reply"
        case calendarEvent = "calendar_event"
    }
}

struct CalendarEventSuggestion: Codable {
    let title: String
    let datetime: String
    let durationMin: Int
    let attendees: [String]?

    enum CodingKeys: String, CodingKey {
        case title, datetime, attendees
        case durationMin = "duration_min"
    }
}

struct SlackChannel: Identifiable, Codable {
    let id: String
    let name: String
    let isMember: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case isMember = "is_member"
    }
}
