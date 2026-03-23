import Foundation

class APIClient {
    static let shared = APIClient()
    private let baseURL = "https://sbrain-production-0f09.up.railway.app/api"

    private init() {}

    // MARK: - Memories (Notes)

    func fetchMemories() async throws -> [Memory] {
        let url = URL(string: "\(baseURL)/notes/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([Memory].self, from: data)
    }

    func fetchMemory(id: String) async throws -> Memory {
        let url = URL(string: "\(baseURL)/notes/\(id)/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(Memory.self, from: data)
    }

    // MARK: - Memorize (Ingest)

    func memorize(folderPath: String) async throws {
        let url = URL(string: "\(baseURL)/ingest/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["folder_path": folderPath]
        request.httpBody = try JSONEncoder().encode(body)
        let _ = try await URLSession.shared.data(for: request)
    }

    func fetchStatus() async throws -> IngestStatus {
        let url = URL(string: "\(baseURL)/status/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(IngestStatus.self, from: data)
    }

    // MARK: - Recall (Search)

    func recall(query: String, limit: Int = 10) async throws -> [SearchResult] {
        let url = URL(string: "\(baseURL)/search/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["query": query, "limit": limit]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([SearchResult].self, from: data)
    }

    // MARK: - Brain Graph

    func fetchBrainGraph(threshold: Double = 0.5) async throws -> BrainGraph {
        let url = URL(string: "\(baseURL)/graph/?threshold=\(threshold)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(BrainGraph.self, from: data)
    }

    // MARK: - Database Browser

    func dbConnect(connectionURL: String) async throws -> DBConnectionInfo {
        let url = URL(string: "\(baseURL)/db/connect/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["connection_url": connectionURL])
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(DBConnectionInfo.self, from: data)
    }

    func dbSchemas(connectionURL: String) async throws -> [DBSchema] {
        let encoded = connectionURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "\(baseURL)/db/schemas/?url=\(encoded)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([DBSchema].self, from: data)
    }

    func dbTables(connectionURL: String, schema: String) async throws -> [DBTable] {
        let encoded = connectionURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "\(baseURL)/db/tables/?url=\(encoded)&schema=\(schema)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([DBTable].self, from: data)
    }

    func dbColumns(connectionURL: String, schema: String, table: String) async throws -> [DBColumn] {
        let encoded = connectionURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "\(baseURL)/db/columns/?url=\(encoded)&schema=\(schema)&table=\(table)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([DBColumn].self, from: data)
    }

    func dbRows(connectionURL: String, schema: String, table: String, limit: Int = 200, offset: Int = 0) async throws -> DBRowsResponse {
        let encoded = connectionURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "\(baseURL)/db/rows/?url=\(encoded)&schema=\(schema)&table=\(table)&limit=\(limit)&offset=\(offset)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(DBRowsResponse.self, from: data)
    }

    func dbSearch(connectionURL: String, query: String, limit: Int = 50) async throws -> [DBSearchResult] {
        let url = URL(string: "\(baseURL)/db/search/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["connection_url": connectionURL, "query": query, "limit": limit]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([DBSearchResult].self, from: data)
    }

    func dbGraph(connectionURL: String) async throws -> BrainGraph {
        let encoded = connectionURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "\(baseURL)/db/graph/?url=\(encoded)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(BrainGraph.self, from: data)
    }

    // MARK: - Slack

    struct SlackStatusResponse: Codable {
        let connected: Bool
        let pendingCount: Int?

        enum CodingKeys: String, CodingKey {
            case connected
            case pendingCount = "pending_count"
        }
    }

    func slackStatus() async throws -> SlackStatusResponse {
        let url = URL(string: "\(baseURL)/slack/status/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SlackStatusResponse.self, from: data)
    }

    struct SlackScanResponse: Codable {
        let messages: [SlackMessage]
    }

    func slackScan() async throws -> [SlackMessage] {
        let url = URL(string: "\(baseURL)/slack/scan/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(SlackScanResponse.self, from: data).messages
    }

    func slackMessages(channel: String? = nil) async throws -> [SlackMessage] {
        var urlString = "\(baseURL)/slack/messages/"
        if let channel = channel {
            urlString += "?channel=\(channel)"
        }
        let url = URL(string: urlString)!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([SlackMessage].self, from: data)
    }

    struct SlackReplyRequest: Codable {
        let messageId: String
        let channel: String
        let threadTs: String?
        let text: String

        enum CodingKeys: String, CodingKey {
            case channel, text
            case messageId = "message_id"
            case threadTs = "thread_ts"
        }
    }

    struct SlackReplyResponse: Codable {
        let ok: Bool
    }

    func slackReply(messageId: String, channel: String, threadTs: String?, text: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)/slack/reply/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = SlackReplyRequest(messageId: messageId, channel: channel, threadTs: threadTs, text: text)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SlackReplyResponse.self, from: data)
        return response.ok
    }

    struct SlackAuthResponse: Codable {
        let authUrl: String

        enum CodingKeys: String, CodingKey {
            case authUrl = "auth_url"
        }
    }

    func slackAuth() async throws -> String {
        let url = URL(string: "\(baseURL)/slack/auth/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SlackAuthResponse.self, from: data).authUrl
    }

    struct SlackUserInfo: Codable {
        let id: String?
        let name: String?
    }

    struct SlackUserResponse: Codable {
        let user: SlackUserInfo?
        let authenticated: Bool
    }

    func slackUser() async throws -> SlackUserResponse {
        let url = URL(string: "\(baseURL)/slack/user/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SlackUserResponse.self, from: data)
    }

    struct SlackChannelsResponse: Codable {
        let channels: [SlackChannel]
    }

    func slackChannels() async throws -> [SlackChannel] {
        let url = URL(string: "\(baseURL)/slack/channels/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SlackChannelsResponse.self, from: data).channels
    }

    // MARK: - Calendar

    struct CalendarAuthStatusResponse: Codable {
        let authenticated: Bool
    }

    func calendarStatus() async throws -> CalendarAuthStatusResponse {
        let url = URL(string: "\(baseURL)/calendar/status/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(CalendarAuthStatusResponse.self, from: data)
    }

    struct CalendarAuthResponse: Codable {
        let authUrl: String

        enum CodingKeys: String, CodingKey {
            case authUrl = "auth_url"
        }
    }

    func calendarAuth() async throws -> String {
        let url = URL(string: "\(baseURL)/calendar/auth/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(CalendarAuthResponse.self, from: data)
        return response.authUrl
    }

    func calendarEvents(start: String, end: String) async throws -> [CalendarEvent] {
        let url = URL(string: "\(baseURL)/calendar/events/?start=\(start)&end=\(end)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([CalendarEvent].self, from: data)
    }

    struct CalendarCreateEventRequest: Codable {
        let title: String
        let start: String
        let end: String
        let description: String?
        let location: String?
        let attendees: [String]?
    }

    func calendarCreateEvent(title: String, start: String, end: String, description: String? = nil, location: String? = nil, attendees: [String]? = nil) async throws -> CalendarEvent {
        let url = URL(string: "\(baseURL)/calendar/events/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = CalendarCreateEventRequest(title: title, start: start, end: end, description: description, location: location, attendees: attendees)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(CalendarEvent.self, from: data)
    }

    func calendarDeleteEvent(id: String) async throws {
        let url = URL(string: "\(baseURL)/calendar/events/\(id)/")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let _ = try await URLSession.shared.data(for: request)
    }

}
