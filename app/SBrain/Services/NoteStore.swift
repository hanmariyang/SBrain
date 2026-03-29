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

    // Cloud notes (iOS용 — Railway API에서 로드)
    @Published var cloudNotes: [Memory] = []
    @Published var isLoadingCloud = false

    // Backend (search only)
    @Published var searchResults: [SearchResult] = []
    @Published var searchQuery = ""
    @Published var isSearching = false
    @Published var searchError: String?
    @Published var ingestStatus: IngestStatus?
    @Published var isIngesting = false

    private let api = APIClient.shared
    /// SyncManager 참조 (SBrainApp에서 주입)
    weak var syncManager: SyncManager?
    private var pollTimer: Timer?
    private let savedProjectsKey = "SBrain.projectPaths"
    private let savedProjectNamesKey = "SBrain.projectNames"
    private let baseFolderPathKey = "SBrain.baseFolderPath"

    /// Base folder path (~/Documents/SBrain/ by default)
    @Published var baseFolderPath: String = ""

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

    // MARK: - Cloud Notes (iOS)

    /// Railway API에서 노트 목록 로드 (iOS용)
    func loadCloudNotes() async {
        guard !api.jwtAccessToken.isEmpty else { return }
        isLoadingCloud = true
        do {
            let url = URL(string: "\(api.cloudBaseURL)/notes/")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(api.jwtAccessToken)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            cloudNotes = try JSONDecoder().decode([Memory].self, from: data)
        } catch {
            // 토큰 만료 시 갱신 후 재시도
            do {
                try await api.cloudRefreshToken()
                let url = URL(string: "\(api.cloudBaseURL)/notes/")!
                var request = URLRequest(url: url)
                request.setValue("Bearer \(api.jwtAccessToken)", forHTTPHeaderField: "Authorization")
                let (data, _) = try await URLSession.shared.data(for: request)
                cloudNotes = try JSONDecoder().decode([Memory].self, from: data)
            } catch {
                cloudNotes = []
            }
        }
        isLoadingCloud = false
    }

    /// Railway API에서 노트 상세 로드 (iOS용)
    func loadCloudNoteContent(id: String) async -> String? {
        guard !api.jwtAccessToken.isEmpty else { return nil }
        do {
            let url = URL(string: "\(api.cloudBaseURL)/notes/\(id)/")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(api.jwtAccessToken)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            let memory = try JSONDecoder().decode(Memory.self, from: data)
            return memory.content
        } catch {
            return nil
        }
    }

    /// Railway API 검색 (iOS용 — 클라우드 기반)
    func recallFromCloud() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        do {
            let url = URL(string: "\(api.cloudBaseURL)/search/")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(api.jwtAccessToken)", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = ["query": searchQuery, "limit": 20]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            searchResults = try JSONDecoder().decode([SearchResult].self, from: data)
            Analytics.searchRecall(resultCount: searchResults.count)
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    // MARK: - Project Management

    func addFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "프로젝트 폴더를 선택하세요 (여러 개 선택 가능)"

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            addProject(path: url.path)
        }
        #endif
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
        initBaseFolder()

        guard let paths = UserDefaults.standard.stringArray(forKey: savedProjectsKey) else {
            rebuildGraph()
            return
        }
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
        let nonBase = projects.filter { !$0.isBaseFolder }
        UserDefaults.standard.set(nonBase.map(\.path), forKey: savedProjectsKey)
        let names = Dictionary(uniqueKeysWithValues: nonBase.map { ($0.path, $0.name) })
        UserDefaults.standard.set(names, forKey: savedProjectNamesKey)
    }

    // MARK: - Base Folder (Personal Workspace)

    private func initBaseFolder() {
        let saved = UserDefaults.standard.string(forKey: baseFolderPathKey)
        let defaultPath = (NSHomeDirectory() as NSString).appendingPathComponent("Documents/SBrain")
        baseFolderPath = saved ?? defaultPath

        let fm = FileManager.default
        if !fm.fileExists(atPath: baseFolderPath) {
            try? fm.createDirectory(atPath: baseFolderPath, withIntermediateDirectories: true)
            // Create welcome file so the folder isn't empty
            let welcomePath = (baseFolderPath as NSString).appendingPathComponent("Welcome.md")
            let welcomeContent = "# Welcome to SBrain\n\nSBrain 기본 폴더입니다. 여기에 자유롭게 문서를 작성하세요.\n"
            fm.createFile(atPath: welcomePath, contents: welcomeContent.data(using: .utf8))
        }

        UserDefaults.standard.set(baseFolderPath, forKey: baseFolderPathKey)

        guard !projects.contains(where: { $0.isBaseFolder }) else { return }

        let root = FolderScanner.scan(at: baseFolderPath)
            ?? FolderNode(name: "SBrain", path: baseFolderPath, isFolder: true, children: [])
        let project = ProjectFolder(path: baseFolderPath, name: "내 기억", rootFolder: root, isBaseFolder: true)
        projects.insert(project, at: 0)
    }

    func isInBaseFolder(_ path: String) -> Bool {
        !baseFolderPath.isEmpty && path.hasPrefix(baseFolderPath)
    }

    func refreshBaseFolder() {
        guard let idx = projects.firstIndex(where: { $0.isBaseFolder }) else { return }
        let root = FolderScanner.scan(at: baseFolderPath)
            ?? FolderNode(name: "SBrain", path: baseFolderPath, isFolder: true, children: [])
        let old = projects[idx]
        projects[idx] = ProjectFolder(path: old.path, name: old.name, rootFolder: root, isBaseFolder: true)
        rebuildGraph()
    }

    func createNewFile(name: String) -> String? {
        var fileName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileName.isEmpty else { return nil }

        // Ensure .md extension
        if !(fileName as NSString).pathExtension.lowercased().contains("md") &&
           !(fileName as NSString).pathExtension.lowercased().contains("html") {
            fileName += ".md"
        }

        let filePath = (baseFolderPath as NSString).appendingPathComponent(fileName)

        // Avoid overwriting
        if FileManager.default.fileExists(atPath: filePath) { return nil }

        let initialContent = "# \((fileName as NSString).deletingPathExtension)\n\n"
        FileManager.default.createFile(atPath: filePath, contents: initialContent.data(using: .utf8))
        refreshBaseFolder()
        selectFile(path: filePath)
        return filePath
    }

    func saveFileContent(path: String, content: String) {
        guard isInBaseFolder(path) else { return }
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        selectedFileContent = content
        refreshBaseFolder()
    }

    func copyToBaseFolder(sourcePath: String) {
        // Determine source project name for subfolder
        let projectName = projects.first { !$0.isBaseFolder && sourcePath.hasPrefix($0.path) }?.name ?? "Imported"
        let destDir = (baseFolderPath as NSString).appendingPathComponent(projectName)
        let fm = FileManager.default

        if !fm.fileExists(atPath: destDir) {
            try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        }

        let fileName = (sourcePath as NSString).lastPathComponent
        var destPath = (destDir as NSString).appendingPathComponent(fileName)

        // Handle duplicate names
        if fm.fileExists(atPath: destPath) {
            let name = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            var counter = 1
            repeat {
                destPath = (destDir as NSString).appendingPathComponent("\(name)_\(counter).\(ext)")
                counter += 1
            } while fm.fileExists(atPath: destPath)
        }

        try? fm.copyItem(atPath: sourcePath, toPath: destPath)
        refreshBaseFolder()
    }

    func deleteFile(path: String) {
        guard isInBaseFolder(path) else { return }
        try? FileManager.default.removeItem(atPath: path)
        if selectedFilePath == path {
            selectedFilePath = nil
            selectedFileContent = nil
        }
        refreshBaseFolder()
    }

    func openInExternalEditor(path: String) {
        #if os(macOS)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        #endif
    }

    // Legacy compat: selectFolder maps to addFolder
    func selectFolder() { addFolder() }

    // MARK: - File Change Handling (from FileMonitor)

    /// FileMonitor 이벤트 수신 → 변경된 프로젝트 부분 리스캔 + 재인덱싱
    func handleFileChange(changedPaths: [String]) {
        let supportedExtensions: Set<String> = ["md", "html", "htm"]

        // 1. 변경된 프로젝트 식별 및 리스캔
        for (index, project) in projects.enumerated() {
            let isAffected = changedPaths.contains { $0.hasPrefix(project.path) }
            guard isAffected else { continue }
            guard let newRoot = FolderScanner.scan(at: project.path) else { continue }

            projects[index] = ProjectFolder(
                path: project.path,
                name: project.name,
                rootFolder: newRoot,
                isBaseFolder: project.isBaseFolder
            )
        }

        // 2. 변경된 문서 파일만 필터링
        let mdPaths = changedPaths.filter {
            supportedExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
        }

        let existing = mdPaths.filter { FileManager.default.fileExists(atPath: $0) }
        let deleted = mdPaths.filter { !FileManager.default.fileExists(atPath: $0) }

        // 3. 부분 재인덱싱 요청 (로컬)
        if !existing.isEmpty || !deleted.isEmpty {
            Task {
                try? await api.partialIngest(paths: existing, deletedPaths: deleted)
            }
        }

        // 4. Railway 클라우드 동기화 (신규)
        if !existing.isEmpty || !deleted.isEmpty {
            Task {
                await syncManager?.pushChanges(
                    changedPaths: existing,
                    deletedPaths: deleted,
                    projects: projects
                )
            }
        }

        // 5. 그래프 리빌드
        rebuildGraph()

        // 6. 선택된 파일이 변경됐으면 내용 새로고침
        if let selected = selectedFilePath, changedPaths.contains(selected) {
            selectedFileContent = FolderScanner.readContent(at: selected)
        }
    }

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
            Analytics.searchRecall(resultCount: searchResults.count)
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
    let isBaseFolder: Bool

    init(path: String, name: String, rootFolder: FolderNode?, isBaseFolder: Bool = false) {
        self.path = path
        self.name = name
        self.rootFolder = rootFolder
        self.isBaseFolder = isBaseFolder
    }
}
