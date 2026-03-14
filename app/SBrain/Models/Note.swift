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

    init(neurons: [Neuron], synapses: [Synapse]) {
        self.neurons = neurons
        self.synapses = synapses
    }
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

// MARK: - Database Browser Models

struct DBConnectionInfo: Codable {
    let ok: Bool
    let serverVersion: String?
    let database: String?
    let error: String?
    let hasLocalMirror: Bool?

    enum CodingKeys: String, CodingKey {
        case ok, database, error
        case serverVersion = "server_version"
        case hasLocalMirror = "has_local_mirror"
    }
}

struct DBSchema: Identifiable, Codable {
    var id: String { name }
    let name: String
    let tableCount: Int

    enum CodingKeys: String, CodingKey {
        case name
        case tableCount = "table_count"
    }
}

struct DBTable: Identifiable, Codable, Hashable {
    var id: String { "\(schema).\(name)" }
    let name: String
    let schema: String
    let type: String
    let columnCount: Int
    let rowEstimate: Int

    enum CodingKeys: String, CodingKey {
        case name, schema, type
        case columnCount = "column_count"
        case rowEstimate = "row_estimate"
    }
}

struct DBColumn: Identifiable, Codable {
    var id: String { "\(ordinal)_\(name)" }
    let name: String
    let type: String
    let nullable: Bool
    let defaultValue: String?
    let ordinal: Int

    enum CodingKeys: String, CodingKey {
        case name, type, nullable, ordinal
        case defaultValue = "default"
    }
}

struct DBRowsResponse: Codable {
    let columns: [String]
    let rows: [[JSONValue]]
    let totalEstimate: Int
    let limit: Int
    let offset: Int
    let isLocal: Bool?

    enum CodingKeys: String, CodingKey {
        case columns, rows, limit, offset
        case totalEstimate = "total_estimate"
        case isLocal = "is_local"
    }
}

struct DBSearchResult: Identifiable, Codable {
    var id: String { "\(schema).\(table).\(column).\(String(describing: value).prefix(20))" }
    let schema: String
    let table: String
    let column: String
    let value: String
    let rowPreview: [String: String]

    enum CodingKeys: String, CodingKey {
        case schema, table, column, value
        case rowPreview = "row_preview"
    }
}

// MARK: - DB Download Status

struct DBDownloadStatus: Codable {
    let running: Bool
    let phase: String
    let progress: String
    let remoteUrl: String
    let localDb: String
    let error: String?
    let elapsed: Int?

    enum CodingKeys: String, CodingKey {
        case running, phase, progress, error, elapsed
        case remoteUrl = "remote_url"
        case localDb = "local_db"
    }
}

/// Lightweight wrapper for heterogeneous JSON values from PostgreSQL rows.
enum JSONValue: Codable, CustomStringConvertible {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    var description: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        case .null: return "NULL"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        }
    }
}
