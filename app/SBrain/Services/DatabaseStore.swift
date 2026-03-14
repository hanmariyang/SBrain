import SwiftUI
import Combine

@MainActor
class DatabaseStore: ObservableObject {
    // Connection
    @Published var connectionURL: String = ""
    @Published var connectionInfo: DBConnectionInfo?
    @Published var isConnecting = false
    @Published var connectionError: String?

    // Schema / Tables
    @Published var schemas: [DBSchema] = []
    @Published var selectedSchema: String = "public"
    @Published var tables: [DBTable] = []
    @Published var selectedTable: DBTable?

    // Columns / Rows
    @Published var columns: [DBColumn] = []
    @Published var rows: DBRowsResponse?
    @Published var isLoadingRows = false
    @Published var currentPage: Int = 0
    let pageSize: Int = 200

    // Row detail
    @Published var selectedRowIndex: Int?

    // Search
    @Published var searchQuery: String = ""
    @Published var searchResults: [DBSearchResult] = []
    @Published var isSearching = false

    // Brain Map
    @Published var dbBrainGraph: BrainGraph?

    // Download / Mirror
    @Published var hasLocalMirror = false
    @Published var downloadStatus: DBDownloadStatus?
    @Published var isDownloading = false

    private let api = APIClient.shared
    private var downloadPollTimer: Timer?

    var isConnected: Bool { connectionInfo?.ok == true }
    var databaseName: String { connectionInfo?.database ?? "" }

    var totalPages: Int {
        guard let r = rows, r.totalEstimate > 0 else { return 1 }
        return max(1, Int(ceil(Double(r.totalEstimate) / Double(pageSize))))
    }

    // MARK: - Connection

    func connect() async {
        let url = connectionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            connectionError = "연결 URL을 입력하세요"
            return
        }
        isConnecting = true
        connectionError = nil
        do {
            let info = try await api.dbConnect(connectionURL: url)
            connectionInfo = info
            if info.ok {
                connectionError = nil
                hasLocalMirror = info.hasLocalMirror ?? false
                await loadSchemas()
                await loadDBGraph()
            } else {
                connectionError = info.error ?? "연결 실패"
            }
        } catch {
            connectionError = "백엔드 연결 실패: \(error.localizedDescription)"
        }
        isConnecting = false
    }

    func disconnect() {
        connectionInfo = nil
        schemas = []
        tables = []
        selectedTable = nil
        columns = []
        rows = nil
        dbBrainGraph = nil
        currentPage = 0
        connectionError = nil
        hasLocalMirror = false
        stopDownloadPoll()
    }

    // MARK: - Download (Mirror)

    func startDownload() async {
        guard isConnected else { return }
        do {
            try await api.dbDownload(connectionURL: connectionURL)
            isDownloading = true
            startDownloadPoll()
        } catch {
            connectionError = "다운로드 시작 실패: \(error.localizedDescription)"
        }
    }

    func syncDB() async {
        // Re-download = same as download (overwrites existing mirror)
        await startDownload()
    }

    private func startDownloadPoll() {
        stopDownloadPoll()
        downloadPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollDownloadStatus()
            }
        }
    }

    private func stopDownloadPoll() {
        downloadPollTimer?.invalidate()
        downloadPollTimer = nil
    }

    private func pollDownloadStatus() async {
        do {
            let status = try await api.dbDownloadStatus()
            downloadStatus = status
            isDownloading = status.running

            if !status.running {
                stopDownloadPoll()
                if status.phase == "done" {
                    hasLocalMirror = true
                    // Reload data from local mirror
                    await loadSchemas()
                    await loadDBGraph()
                }
            }
        } catch {
            // ignore poll errors
        }
    }

    func deleteMirror() async {
        guard isConnected else { return }
        try? await api.dbDeleteMirror(connectionURL: connectionURL)
        hasLocalMirror = false
        // Reload from remote
        await loadSchemas()
    }

    // MARK: - Schema / Tables

    func loadSchemas() async {
        guard isConnected else { return }
        do {
            schemas = try await api.dbSchemas(connectionURL: connectionURL)
            if !schemas.isEmpty {
                if !schemas.contains(where: { $0.name == selectedSchema }) {
                    selectedSchema = schemas[0].name
                }
                await loadTables()
            }
        } catch {
            connectionError = "스키마 로드 실패: \(error.localizedDescription)"
        }
    }

    func loadTables() async {
        guard isConnected else { return }
        do {
            tables = try await api.dbTables(connectionURL: connectionURL, schema: selectedSchema)
        } catch {
            connectionError = "테이블 로드 실패: \(error.localizedDescription)"
        }
    }

    func selectSchema(_ schema: String) async {
        selectedSchema = schema
        selectedTable = nil
        columns = []
        rows = nil
        currentPage = 0
        await loadTables()
    }

    // MARK: - Table Detail

    var selectedRow: (columns: [String], values: [JSONValue])? {
        guard let rows, let idx = selectedRowIndex,
              idx >= 0, idx < rows.rows.count else { return nil }
        return (columns: rows.columns, values: rows.rows[idx])
    }

    func selectTable(_ table: DBTable) async {
        selectedTable = table
        selectedRowIndex = nil
        currentPage = 0
        async let cols: () = loadColumns(table)
        async let data: () = loadPage(0, table: table)
        _ = await (cols, data)
    }

    func selectRow(_ index: Int?) {
        selectedRowIndex = index
    }

    private func loadColumns(_ table: DBTable) async {
        do {
            columns = try await api.dbColumns(connectionURL: connectionURL, schema: table.schema, table: table.name)
        } catch {
            columns = []
        }
    }

    func loadPage(_ page: Int, table: DBTable? = nil) async {
        let tbl = table ?? selectedTable
        guard let tbl else { return }
        isLoadingRows = true
        currentPage = page
        do {
            rows = try await api.dbRows(
                connectionURL: connectionURL,
                schema: tbl.schema,
                table: tbl.name,
                limit: pageSize,
                offset: page * pageSize
            )
        } catch {
            rows = nil
        }
        isLoadingRows = false
    }

    // MARK: - Search

    func searchDB() async {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, isConnected else {
            searchResults = []
            return
        }
        isSearching = true
        do {
            searchResults = try await api.dbSearch(connectionURL: connectionURL, query: q)
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
    }

    // MARK: - Brain Graph

    func loadDBGraph() async {
        guard isConnected else { return }
        do {
            dbBrainGraph = try await api.dbGraph(connectionURL: connectionURL)
        } catch {
            dbBrainGraph = nil
        }
    }
}
