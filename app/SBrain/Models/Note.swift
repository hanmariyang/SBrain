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

    var docFileCount: Int {
        if isFolder {
            return children.reduce(0) { $0 + $1.docFileCount }
        }
        let ext = (name as NSString).pathExtension.lowercased()
        return FolderScanner.supportedExtensions.contains(ext) ? 1 : 0
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
    let z: Double
    let chunkCount: Int
    let projectTag: String

    enum CodingKeys: String, CodingKey {
        case id, filename, preview, x, y, z
        case chunkCount = "chunk_count"
        case projectTag = "project_tag"
    }

    init(id: String, filename: String, preview: String, x: Double, y: Double, z: Double = 0.5, chunkCount: Int, projectTag: String = "") {
        self.id = id; self.filename = filename; self.preview = preview
        self.x = x; self.y = y; self.z = z; self.chunkCount = chunkCount; self.projectTag = projectTag
    }
}

struct Synapse: Identifiable, Codable {
    var id: String { "\(source)-\(target)" }
    let source: String
    let target: String
    let strength: Double
}
