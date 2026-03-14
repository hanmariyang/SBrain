import Foundation

class APIClient {
    static let shared = APIClient()
    private let baseURL = "http://127.0.0.1:8765/api"

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

    // MARK: - DB Mirror (Download / Sync)

    func dbDownload(connectionURL: String) async throws {
        let url = URL(string: "\(baseURL)/db/download/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["connection_url": connectionURL])
        let _ = try await URLSession.shared.data(for: request)
    }

    func dbDownloadStatus() async throws -> DBDownloadStatus {
        let url = URL(string: "\(baseURL)/db/download/status/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(DBDownloadStatus.self, from: data)
    }

    func dbDeleteMirror(connectionURL: String) async throws {
        let url = URL(string: "\(baseURL)/db/mirror/delete/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["connection_url": connectionURL])
        let _ = try await URLSession.shared.data(for: request)
    }
}
