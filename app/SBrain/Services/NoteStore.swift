import SwiftUI
import Combine

@MainActor
class NoteStore: ObservableObject {
    // Multi-project: multiple folders
    @Published var projects: [ProjectFolder] = []
    @Published var selectedProjectId: UUID?  // nil = show all
    @Published var selectedFilePath: String?
    @Published var selectedFileContent: String?

    // Multi-selection (hand gesture dwell select)
    @Published var multiSelectedPaths: [String] = []
    @Published var browseIndex: Int = 0

    // Brain graph (merged from all projects)
    @Published var brainGraph: BrainGraph?
    @Published var dbBrainGraph: BrainGraph?  // injected from DatabaseStore

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
    private let savedProjectNamesKey = "SBrain.projectNames"

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

    /// Merged graph: file neurons + DB neurons (DB offset to avoid overlap)
    var mergedBrainGraph: BrainGraph? {
        guard let fileGraph = brainGraph else { return dbBrainGraph }
        guard let db = dbBrainGraph, !db.neurons.isEmpty else { return fileGraph }

        // Offset DB neurons so they form separate clusters from file neurons.
        // Group DB neurons by schema and place each schema as a distinct sphere.
        let dbSchemas = Dictionary(grouping: db.neurons) { neuron -> String in
            // id format: "db:schema_name.table_name"
            let parts = neuron.id.dropFirst(3).split(separator: ".", maxSplits: 1)
            return parts.first.map(String.init) ?? "default"
        }
        let schemaList = dbSchemas.keys.sorted()
        let fileMaxX = fileGraph.neurons.map(\.x).max() ?? 1.0

        // Place DB schemas to the right of file neurons, each as a separate sphere
        var offsetNeurons: [Neuron] = []
        let dbBaseX = fileMaxX + 1.5  // gap between file and DB clusters
        let schemaSpacing = 2.5

        for (idx, schema) in schemaList.enumerated() {
            guard let neurons = dbSchemas[schema] else { continue }
            let centerX = dbBaseX + Double(idx) * schemaSpacing

            for neuron in neurons {
                // neuron.x/y/z are in [-1,1], scale to sphere radius ~0.8
                let moved = Neuron(
                    id: neuron.id,
                    filename: neuron.filename,
                    preview: neuron.preview,
                    x: centerX + neuron.x * 0.8,
                    y: neuron.y * 0.8,
                    z: neuron.z * 0.8,
                    chunkCount: neuron.chunkCount,
                    projectTag: neuron.projectTag
                )
                offsetNeurons.append(moved)
            }
        }

        return BrainGraph(
            neurons: fileGraph.neurons + offsetNeurons,
            synapses: fileGraph.synapses + db.synapses
        )
    }

    /// Filtered graph: only neurons/synapses for selected project (or all if nil)
    var filteredBrainGraph: BrainGraph? {
        guard let graph = mergedBrainGraph else { return nil }
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

    func renameProject(id: UUID, newName: String) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        projects[idx].name = trimmed
        saveProjectPaths()
    }

    func restoreProjects() {
        guard let paths = UserDefaults.standard.stringArray(forKey: savedProjectsKey) else { return }
        let savedNames = UserDefaults.standard.dictionary(forKey: savedProjectNamesKey) as? [String: String] ?? [:]
        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            guard !projects.contains(where: { $0.path == path }) else { continue }
            if let root = FolderScanner.scan(at: path) {
                let name = savedNames[path] ?? URL(fileURLWithPath: path).lastPathComponent
                let project = ProjectFolder(path: path, name: name, rootFolder: root)
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
        let names = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0.name) })
        UserDefaults.standard.set(names, forKey: savedProjectNamesKey)
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

    /// Toggle a path in multi-selection (for dwell select)
    func toggleMultiSelect(path: String) {
        if let idx = multiSelectedPaths.firstIndex(of: path) {
            multiSelectedPaths.remove(at: idx)
            // Adjust browseIndex
            if multiSelectedPaths.isEmpty {
                browseIndex = 0
            } else {
                browseIndex = min(browseIndex, multiSelectedPaths.count - 1)
            }
        } else {
            multiSelectedPaths.append(path)
            browseIndex = multiSelectedPaths.count - 1
            // Also select the file for viewing
            selectFile(path: path)
        }
    }

    /// Browse next in multi-selection
    func browseNext() {
        guard !multiSelectedPaths.isEmpty else { return }
        browseIndex = (browseIndex + 1) % multiSelectedPaths.count
        selectFile(path: multiSelectedPaths[browseIndex])
    }

    /// Browse previous in multi-selection
    func browsePrevious() {
        guard !multiSelectedPaths.isEmpty else { return }
        browseIndex = (browseIndex - 1 + multiSelectedPaths.count) % multiSelectedPaths.count
        selectFile(path: multiSelectedPaths[browseIndex])
    }

    /// Clear multi-selection
    func clearMultiSelection() {
        multiSelectedPaths.removeAll()
        browseIndex = 0
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
    var name: String
    let rootFolder: FolderNode?
}
