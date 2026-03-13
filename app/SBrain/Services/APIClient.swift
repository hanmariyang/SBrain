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
}
