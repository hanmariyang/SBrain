import SwiftUI
import Combine

@MainActor
class NoteStore: ObservableObject {
    // Multi-project: multiple folders
    @Published var projects: [ProjectFolder] = []
    @Published var selectedProjectId: UUID?  // nil = show all
    @Published var selectedFilePath: String?
    @Published var selectedFileContent: String?

    // Brain graph (merged from all projects)
    @Published var brainGraph: BrainGraph?

    // Backend (search only)
    @Published var searchResults: [SearchResult] = []
    @Published var searchQuery = ""
    @Published var isSearching = false
    @Published var searchError: String?
    @Published var ingestStatus: IngestStatus?
    @Published var isIngesting = false

    private let api = APIClient.shared
    private var pollTimer: Timer?
    private let savedProjectsKey = "SBrain.projectPaths"

    var totalDocCount: Int {
        projects.reduce(0) { $0 + ($1.rootFolder?.docFileCount ?? 0) }
    }

    var allRootFolders: [FolderNode] {
        projects.compactMap { $0.rootFolder }
    }

    var hasProjects: Bool { !projects.isEmpty }

    var selectedProject: ProjectFolder? {
        guard let id = selectedProjectId else { return nil }
        return projects.first { $0.id == id }
    }

    /// Filtered graph: only neurons/synapses for selected project (or all if nil)
    var filteredBrainGraph: BrainGraph? {
        guard let graph = brainGraph else { return nil }
        guard let project = selectedProject else { return graph }

        let projectPrefix = project.path
        let filteredNeurons = graph.neurons.filter { $0.id.hasPrefix(projectPrefix) }
        let neuronIds = Set(filteredNeurons.map(\.id))
        let filteredSynapses = graph.synapses.filter {
            neuronIds.contains($0.source) && neuronIds.contains($0.target)
        }
        return BrainGraph(neurons: filteredNeurons, synapses: filteredSynapses)
    }

    /// Filtered projects list for display
    var visibleProjects: [ProjectFolder] {
        guard let id = selectedProjectId else { return projects }
        return projects.filter { $0.id == id }
    }

    func selectProject(_ id: UUID?) {
        selectedProjectId = (selectedProjectId == id) ? nil : id
    }

    /// Search results filtered by selected project
    var filteredSearchResults: [SearchResult] {
        guard let project = selectedProject else { return searchResults }
        return searchResults.filter { $0.path.hasPrefix(project.path) }
    }

    /// Paths of search result files — used for Brain Map highlighting
    var searchResultPaths: Set<String> {
        guard !searchResults.isEmpty, !searchQuery.isEmpty else { return [] }
        if let project = selectedProject {
            return Set(searchResults.filter { $0.path.hasPrefix(project.path) }.map(\.path))
        }
        return Set(searchResults.map(\.path))
    }

    /// Whether search is active (has query and results)
    var isSearchActive: Bool {
        !searchQuery.isEmpty && !searchResults.isEmpty
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
        searchError = nil
    }

    // MARK: - Project Management

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "프로젝트 폴더를 선택하세요 (여러 개 선택 가능)"

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            addProject(path: url.path)
        }
    }

    func addProject(path: String) {
        guard !projects.contains(where: { $0.path == path }) else { return }
        guard let root = FolderScanner.scan(at: path) else { return }

        let project = ProjectFolder(path: path, name: URL(fileURLWithPath: path).lastPathComponent, rootFolder: root)
        projects.append(project)
        saveProjectPaths()
        rebuildGraph()

        Task { await memorizeInBackground(folderPath: path) }
    }

    func removeProject(at index: Int) {
        guard projects.indices.contains(index) else { return }
        projects.remove(at: index)
        saveProjectPaths()
        rebuildGraph()
    }

    func removeProject(path: String) {
        projects.removeAll { $0.path == path }
        saveProjectPaths()
        rebuildGraph()
    }

    func restoreProjects() {
        guard let paths = UserDefaults.standard.stringArray(forKey: savedProjectsKey) else { return }
        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            guard !projects.contains(where: { $0.path == path }) else { continue }
            if let root = FolderScanner.scan(at: path) {
                let project = ProjectFolder(path: path, name: URL(fileURLWithPath: path).lastPathComponent, rootFolder: root)
                projects.append(project)
            }
        }
        rebuildGraph()

        for project in projects {
            Task { await memorizeInBackground(folderPath: project.path) }
        }
    }

    private func saveProjectPaths() {
        UserDefaults.standard.set(projects.map(\.path), forKey: savedProjectsKey)
    }

    // Legacy compat: selectFolder maps to addFolder
    func selectFolder() { addFolder() }

    // MARK: - Graph

    func rebuildGraph() {
        let roots = allRootFolders
        guard !roots.isEmpty else {
            brainGraph = nil
            return
        }
        brainGraph = LocalGraphBuilder.build(from: roots)
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
            searchError = nil
            return
        }
        isSearching = true
        searchError = nil
        do {
            searchResults = try await api.recall(query: searchQuery)
            if searchResults.isEmpty {
                searchError = "검색 결과가 없습니다 — 프로젝트를 먼저 인덱싱하세요"
            }
        } catch let error as URLError where error.code.rawValue == -1004 {
            searchResults = []
            searchError = "백엔드 서버에 연결할 수 없습니다"
            print("Recall failed: backend not running")
        } catch {
            searchResults = []
            searchError = "회상 실패: \(error.localizedDescription)"
            print("Recall failed: \(error)")
        }
        isSearching = false
    }

    // MARK: - Background Ingest

    private func memorizeInBackground(folderPath: String) async {
        do {
            try await api.memorize(folderPath: folderPath)
            isIngesting = true
            startPollingStatus()
        } catch {
            // Backend not available
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
                await tryUpgradeGraph()
            }
        } catch {
            isIngesting = false
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func tryUpgradeGraph() async {
        do {
            let apiGraph = try await api.fetchBrainGraph(threshold: 0.3)
            if !apiGraph.neurons.isEmpty {
                brainGraph = apiGraph
            }
        } catch {}
    }
}

// MARK: - Project Model

struct ProjectFolder: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    let rootFolder: FolderNode?
}
