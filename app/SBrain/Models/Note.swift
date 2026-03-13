import Foundation

// MARK: - Folder Tree (local filesystem)

class FolderNode: Identifiable, ObservableObject {
    let id = UUID()
    let name: String
    let path: String
    let isFolder: Bool
    let children: [FolderNode]
    let preview: String   // first 3 lines for .md files
    let modifiedAt: Date?

    var mdFileCount: Int {
        if isFolder {
            return children.reduce(0) { $0 + $1.mdFileCount }
        }
        return name.hasSuffix(".md") ? 1 : 0
    }

    init(name: String, path: String, isFolder: Bool, children: [FolderNode] = [], preview: String = "", modifiedAt: Date? = nil) {
        self.name = name
        self.path = path
        self.isFolder = isFolder
        self.children = children
        self.preview = preview
        self.modifiedAt = modifiedAt
    }
}

// MARK: - API Models (for backend communication)

struct Memory: Identifiable, Codable {
    let id: String
    let filename: String
    let path: String
    let updatedAt: String?
    let preview: String?
    let content: String?

    enum CodingKeys: String, CodingKey {
        case id, filename, path, content
        case updatedAt = "updated_at"
        case preview
    }
}

struct SearchResult: Identifiable, Codable {
    var id: String { noteId + chunkText.prefix(20) }
    let noteId: String
    let filename: String
    let path: String
    let chunkText: String
    let score: Double

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case filename, path
        case chunkText = "chunk_text"
        case score
    }
}

struct IngestStatus: Codable {
    let running: Bool
    let total: Int
    let done: Int
    let currentFile: String

    enum CodingKeys: String, CodingKey {
        case running, total, done
        case currentFile = "current_file"
    }
}

// MARK: - Brain Graph Models

struct BrainGraph: Codable {
    let neurons: [Neuron]
    let synapses: [Synapse]
}

struct Neuron: Identifiable, Codable {
    let id: String
    let filename: String
    let preview: String
    let x: Double
    let y: Double
    let chunkCount: Int

    enum CodingKeys: String, CodingKey {
        case id, filename, preview, x, y
        case chunkCount = "chunk_count"
    }
}

struct Synapse: Identifiable, Codable {
    var id: String { "\(source)-\(target)" }
    let source: String
    let target: String
    let strength: Double
}
