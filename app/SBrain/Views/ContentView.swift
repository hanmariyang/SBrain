import SwiftUI

enum ViewMode: String, CaseIterable {
    case brain = "brain"
    case list = "list"
    case database = "database"

    var icon: String {
        switch self {
        case .brain: return "brain"
        case .list: return "list.bullet"
        case .database: return "cylinder.split.1x2"
        }
    }

    var label: String {
        switch self {
        case .brain: return "Brain Map"
        case .list: return "List"
        case .database: return "Database"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var backendManager: BackendManager
    @EnvironmentObject var dbStore: DatabaseStore
    @State private var viewMode: ViewMode = .list

    var body: some View {
        HSplitView {
            // Left: Projects + content
            VStack(spacing: 0) {
                TopBar(viewMode: $viewMode)

                if noteStore.isIngesting, let status = noteStore.ingestStatus {
                    MemorizeProgressView(status: status)
                }

                if viewMode == .database {
                    // Database browser (available even without projects)
                    if noteStore.hasProjects { ProjectTabBar() }
                    DatabaseBrowserView()
                } else if noteStore.hasProjects {
                    // Project tabs
                    ProjectTabBar()

                    switch viewMode {
                    case .list:
                        FolderTreeView()
                    case .brain:
                        BrainMapView()
                    case .database:
                        EmptyView() // handled above
                    }
                } else {
                    emptyState
                }
            }
            .frame(minWidth: 500)
            .background(Color(nsColor: NSColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1)))

            // Right: Detail panel
            if viewMode == .database {
                DBDetailView()
                    .frame(minWidth: 350, idealWidth: 450)
            } else if viewMode == .brain,
                      let path = noteStore.selectedFilePath,
                      path.hasPrefix("db:"),
                      dbStore.isConnected {
                // DB neuron selected in Brain Map → show DB table detail
                DBDetailView()
                    .frame(minWidth: 350, idealWidth: 450)
                    .onAppear { navigateToDBTable(path) }
                    .onChange(of: noteStore.selectedFilePath) { _, newPath in
                        if let p = newPath, p.hasPrefix("db:") {
                            navigateToDBTable(p)
                        }
                    }
            } else {
                MemoryDetailView()
                    .frame(minWidth: 350, idealWidth: 450)
            }
        }
        .frame(minWidth: 900, minHeight: 550)
        .preferredColorScheme(.dark)
        .task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            noteStore.restoreProjects()
        }
        .onChange(of: dbStore.dbBrainGraph?.neurons.count) { _, _ in
            noteStore.dbBrainGraph = dbStore.dbBrainGraph
        }
    }

    /// Parse "db:schema.table" neuron ID and navigate dbStore to that table
    private func navigateToDBTable(_ path: String) {
        let stripped = String(path.dropFirst(3)) // remove "db:"
        let parts = stripped.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else { return }
        let schema = String(parts[0])
        let tableName = String(parts[1])

        Task {
            if dbStore.selectedSchema != schema {
                await dbStore.selectSchema(schema)
            }
            if let table = dbStore.tables.first(where: { $0.name == tableName }) {
                await dbStore.selectTable(table)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "brain")
                .font(.system(size: 64))
                .foregroundStyle(
                    .linearGradient(
                        colors: [.purple, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.4)

            Text("프로젝트를 추가하세요")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.5))

            Text("여러 프로젝트 폴더를 추가하면\n하나의 Brain Map에서 통합 탐색할 수 있습니다")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)

            Button(action: { noteStore.addFolder() }) {
                Label("프로젝트 추가", systemImage: "folder.badge.plus")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [.purple.opacity(0.5), .cyan.opacity(0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            Spacer()
        }
    }
}

// MARK: - Project Tab Bar

struct ProjectTabBar: View {
    @EnvironmentObject var noteStore: NoteStore
    @State private var showNewFileDialog = false
    @State private var newFileName = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // "All" tab
                AllProjectsTab()

                // Base folder tab (always first, special style)
                if let baseProject = noteStore.projects.first(where: { $0.isBaseFolder }) {
                    BaseFolderTab(project: baseProject, isActive: noteStore.selectedProjectId == baseProject.id)
                }

                // Other project tabs
                ForEach(noteStore.projects.filter { !$0.isBaseFolder }, id: \.id) { project in
                    ProjectTab(project: project, isActive: noteStore.selectedProjectId == project.id, onTap: {
                        noteStore.selectProject(project.id)
                    }, onRemove: {
                        noteStore.removeProject(path: project.path)
                    }, onRename: { newName in
                        noteStore.renameProject(id: project.id, newName: newName)
                    })
                }

                // Add project button
                Button(action: { noteStore.addFolder() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("프로젝트 추가")

                // New file button (visible when base folder is selected)
                if let sel = noteStore.selectedProjectId,
                   noteStore.projects.first(where: { $0.id == sel })?.isBaseFolder == true {
                    Button(action: { showNewFileDialog = true }) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 10))
                            .foregroundStyle(.green.opacity(0.6))
                            .frame(width: 24, height: 24)
                            .background(.green.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("새 문서 만들기")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color.black.opacity(0.2))
        .sheet(isPresented: $showNewFileDialog) {
            NewFileDialog(isPresented: $showNewFileDialog)
        }
    }
}

struct BaseFolderTab: View {
    @EnvironmentObject var noteStore: NoteStore
    let project: ProjectFolder
    let isActive: Bool

    var body: some View {
        Button(action: { noteStore.selectProject(project.id) }) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 10))
                    .foregroundStyle(.green.opacity(0.8))

                Text(project.name)
                    .font(.system(size: 11, weight: isActive ? .bold : .medium))
                    .foregroundStyle(.white.opacity(isActive ? 0.95 : 0.6))
                    .lineLimit(1)

                if let root = project.rootFolder {
                    Text("\(root.docFileCount)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.green.opacity(0.15) : .white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isActive ? Color.green.opacity(0.5) : Color.green.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct NewFileDialog: View {
    @EnvironmentObject var noteStore: NoteStore
    @Binding var isPresented: Bool
    @State private var fileName = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("새 문서 만들기")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)

            TextField("파일명 (예: my-note.md)", text: $fileName)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { create() }

            HStack(spacing: 12) {
                Button("취소") { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Button("만들기") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(fileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
        .onAppear { isFocused = true }
    }

    private func create() {
        if noteStore.createNewFile(name: fileName) != nil {
            isPresented = false
        }
    }
}

struct AllProjectsTab: View {
    @EnvironmentObject var noteStore: NoteStore

    private var isActive: Bool { noteStore.selectedProjectId == nil }

    var body: some View {
        Button(action: { noteStore.selectProject(nil) }) {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.system(size: 10))
                    .foregroundStyle(.cyan.opacity(0.7))

                Text("All")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(isActive ? 0.9 : 0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.cyan.opacity(0.15) : .white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isActive ? Color.cyan.opacity(0.4) : .clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct ProjectTab: View {
    let project: ProjectFolder
    let isActive: Bool
    let onTap: () -> Void
    let onRemove: () -> Void
    var onRename: ((String) -> Void)? = nil
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editName = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(projectColor)
                    .frame(width: 6, height: 6)

                if isEditing {
                    TextField("", text: $editName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .focused($isFieldFocused)
                        .frame(minWidth: 60, maxWidth: 140)
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                } else {
                    Text(project.name)
                        .font(.system(size: 11, weight: isActive ? .bold : .medium))
                        .foregroundStyle(.white.opacity(isActive ? 0.95 : 0.7))
                        .lineLimit(1)
                }

                if let root = project.rootFolder, !isEditing {
                    Text("\(root.docFileCount)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }

                if isHovered && !isEditing {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? projectColor.opacity(0.15) : .white.opacity(isHovered ? 0.08 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isEditing ? Color.cyan.opacity(0.6) : (isActive ? projectColor.opacity(0.5) : projectColor.opacity(0.3)), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            startEditing()
        }
        .onTapGesture(count: 1) {
            onTap()
        }
    }

    private func startEditing() {
        editName = project.name
        isEditing = true
        isFieldFocused = true
    }

    private func commitRename() {
        let trimmed = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onRename?(trimmed)
        }
        isEditing = false
    }

    private func cancelRename() {
        isEditing = false
    }

    private var projectColor: Color {
        let hash = abs(project.path.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.8)
    }
}

// MARK: - Top Bar

struct TopBar: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var backendManager: BackendManager
    @EnvironmentObject var handTracking: HandTrackingManager
    @Binding var viewMode: ViewMode

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(backendManager.isRunning ? Color.cyan : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: backendManager.isRunning ? .cyan.opacity(0.6) : .clear, radius: 4)

                Text("SBrain")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.cyan, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }

            if noteStore.hasProjects {
                Text("\(noteStore.projects.count) projects · \(noteStore.totalDocCount) files")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer()

            RecallBar()

            Spacer()

            // View mode toggle
            HStack(spacing: 2) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Button(action: { viewMode = mode }) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12))
                            .frame(width: 28, height: 22)
                            .background(
                                viewMode == mode
                                    ? Color.white.opacity(0.15)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(viewMode == mode ? .white : .white.opacity(0.4))
                    .help(mode.label)
                }
            }
            .padding(2)
            .background(.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Hand tracking toggle
            Button(action: { handTracking.isEnabled.toggle() }) {
                Image(systemName: handTracking.isEnabled ? "hand.raised.fill" : "hand.raised")
                    .font(.system(size: 12))
                    .padding(6)
                    .background(handTracking.isEnabled
                        ? (handTracking.isTracking ? Color.green.opacity(0.2) : Color.orange.opacity(0.15))
                        : .white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(handTracking.isEnabled ? Color.green.opacity(0.4) : .clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(handTracking.isEnabled
                ? (handTracking.isTracking ? .green : .orange)
                : .white.opacity(0.6))
            .help(handTracking.isEnabled ? "손 추적 끄기" : "손 추적 켜기")
            .opacity(handTracking.cameraAuthorized ? 1 : 0.3)
            .disabled(!handTracking.cameraAuthorized && !handTracking.isEnabled)

            // Add folder button
            Button(action: { noteStore.addFolder() }) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 12))
                    .padding(6)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
            .help("프로젝트 추가")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.3))
    }
}

// MARK: - Recall Bar (Search)

struct RecallBar: View {
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(noteStore.isSearchActive ? .yellow.opacity(0.8) : .cyan.opacity(0.6))
                    .font(.system(size: 12))

                TextField("회상하기...", text: $noteStore.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .onSubmit {
                        Task { await noteStore.recall() }
                    }

                if noteStore.isSearchActive {
                    Text("\(noteStore.filteredSearchResults.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.15))
                        .clipShape(Capsule())
                }

                if !noteStore.searchQuery.isEmpty {
                    Button(action: { noteStore.clearSearch() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.3))
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }

                if noteStore.isSearching {
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(.cyan)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(noteStore.isSearchActive ? Color.yellow.opacity(0.06) : .white.opacity(0.06))
            .clipShape(Capsule())

            // Error / empty result message
            if let error = noteStore.searchError, !noteStore.isSearching {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: 320)
    }
}

// MARK: - Memorize Progress

struct MemorizeProgressView: View {
    let status: IngestStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain")
                .foregroundStyle(.purple)
                .font(.system(size: 12))
                .symbolEffect(.pulse)

            if status.total > 0 {
                ProgressView(value: Double(status.done), total: Double(status.total))
                    .tint(
                        LinearGradient(
                            colors: [.purple, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("\(status.done)/\(status.total)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text("뇌 활성화 중...")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))

                ProgressView()
                    .scaleEffect(0.5)
                    .tint(.purple)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.purple.opacity(0.1))
    }
}
