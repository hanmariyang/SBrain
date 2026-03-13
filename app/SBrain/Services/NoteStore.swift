import SwiftUI
import Combine

@MainActor
class NoteStore: ObservableObject {
    // Local filesystem
    @Published var rootFolder: FolderNode?
    @Published var selectedFilePath: String?
    @Published var selectedFileContent: String?
    @Published var folderPath: String?

    // Brain graph (local-first, API can upgrade)
    @Published var brainGraph: BrainGraph?

    // Backend (search only)
    @Published var searchResults: [SearchResult] = []
    @Published var searchQuery = ""
    @Published var isSearching = false
    @Published var ingestStatus: IngestStatus?
    @Published var isIngesting = false

    private let api = APIClient.shared
    private var pollTimer: Timer?
    private let savedFolderKey = "SBrain.lastFolderPath"

    // MARK: - Folder Management

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "마크다운 파일이 있는 폴더를 선택하세요"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFolder(path: url.path)
    }

    func openFolder(path: String) {
        folderPath = path
        UserDefaults.standard.set(path, forKey: savedFolderKey)
        scanFolder()

        // Background: backend embedding (non-blocking, won't overwrite local graph)
        Task { await memorizeInBackground(folderPath: path) }
    }

    func restoreLastFolder() {
        guard let saved = UserDefaults.standard.string(forKey: savedFolderKey),
              FileManager.default.fileExists(atPath: saved) else { return }
        folderPath = saved
        scanFolder()

        Task { await memorizeInBackground(folderPath: saved) }
    }

    func scanFolder() {
        guard let path = folderPath else { return }
        rootFolder = FolderScanner.scan(at: path)

        // Build brain graph immediately from folder structure (always available)
        if let root = rootFolder {
            brainGraph = LocalGraphBuilder.build(from: root)
        }
    }

    // MARK: - File Selection

    func selectFile(path: String) {
        selectedFilePath = path
        selectedFileContent = FolderScanner.readContent(at: path)
    }

    var selectedFileName: String? {
        guard let path = selectedFilePath else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    // MARK: - Recall (Search)

    func recall() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        do {
            searchResults = try await api.recall(query: searchQuery)
        } catch {
            print("Recall failed: \(error)")
        }
        isSearching = false
    }

    // MARK: - Background Ingest (won't touch brainGraph)

    private func memorizeInBackground(folderPath: String) async {
        do {
            try await api.memorize(folderPath: folderPath)
            isIngesting = true
            startPollingStatus()
        } catch {
            // Backend not available — that's fine, local graph is already showing
        }
    }

    private func startPollingStatus() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.pollStatus() }
        }
    }

    private func pollStatus() async {
        do {
            let status = try await api.fetchStatus()
            ingestStatus = status
            if !status.running && isIngesting {
                isIngesting = false
                pollTimer?.invalidate()
                pollTimer = nil
                // Embedding done — try to upgrade graph with API version
                await tryUpgradeGraph()
            }
        } catch {
            // Backend down, stop polling
            isIngesting = false
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    /// Only replace local graph if API returns a richer result
    private func tryUpgradeGraph() async {
        do {
            let apiGraph = try await api.fetchBrainGraph(threshold: 0.3)
            // Only upgrade if API actually has neurons
            if !apiGraph.neurons.isEmpty {
                brainGraph = apiGraph
            }
        } catch {
            // Keep local graph as-is
        }
    }
}
