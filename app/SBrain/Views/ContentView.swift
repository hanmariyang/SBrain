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
    @EnvironmentObject var terminalManager: TerminalManager
    @State private var viewMode: ViewMode = .list
    @State private var showBottomTerminal = false
    @State private var bottomTerminalHeight: CGFloat = 250
    @State private var isFullTerminal = false

    var body: some View {
        HSplitView {
            // Left: Projects + content
            VStack(spacing: 0) {
                TopBar(
                    viewMode: $viewMode,
                    showBottomTerminal: $showBottomTerminal,
                    isFullTerminal: $isFullTerminal
                )

                if noteStore.isIngesting, let status = noteStore.ingestStatus {
                    MemorizeProgressView(status: status)
                }

                if isFullTerminal {
                    // Full terminal mode — left side shows nothing (terminal fills right)
                    emptyTerminalLeftState
                } else if viewMode == .database {
                    if noteStore.hasProjects { ProjectTabBar() }
                    DatabaseBrowserView()
                } else if noteStore.hasProjects {
                    ProjectTabBar()

                    switch viewMode {
                    case .list:
                        FolderTreeView()
                    case .brain:
                        BrainMapView()
                    case .database:
                        EmptyView()
                    }
                } else {
                    emptyState
                }
            }
            .frame(minWidth: 500)
            .background(Color(nsColor: NSColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1)))

            // Right: Detail panel + bottom terminal
            if isFullTerminal {
                // Full terminal takes the entire right side
                TerminalContainerView()
                    .frame(minWidth: 350, idealWidth: 450)
            } else {
                VStack(spacing: 0) {
                    // Detail content
                    detailView
                        .frame(maxHeight: .infinity)

                    // Bottom terminal panel
                    if showBottomTerminal {
                        BottomTerminalPanel(
                            height: $bottomTerminalHeight,
                            showBottomTerminal: $showBottomTerminal,
                            isFullTerminal: $isFullTerminal
                        )
                    }
                }
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

    @ViewBuilder
    private var detailView: some View {
        if viewMode == .database {
            DBDetailView()
        } else if viewMode == .brain,
                  let path = noteStore.selectedFilePath,
                  path.hasPrefix("db:"),
                  dbStore.isConnected {
            DBDetailView()
                .onAppear { navigateToDBTable(path) }
                .onChange(of: noteStore.selectedFilePath) { _, newPath in
                    if let p = newPath, p.hasPrefix("db:") {
                        navigateToDBTable(p)
                    }
                }
        } else {
            MemoryDetailView()
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

    private var emptyTerminalLeftState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.orange.opacity(0.15))
            Text("전체 터미널 모드")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
            Text("우측에서 터미널을 사용 중입니다")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.15))
            Spacer()
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // "All" tab
                AllProjectsTab()

                ForEach(Array(noteStore.projects.enumerated()), id: \.element.id) { index, project in
                    ProjectTab(project: project, isActive: noteStore.selectedProjectId == project.id, onTap: {
                        noteStore.selectProject(project.id)
                    }, onRemove: {
                        noteStore.removeProject(at: index)
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color.black.opacity(0.2))
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
    @Binding var showBottomTerminal: Bool
    @Binding var isFullTerminal: Bool

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

            // View mode toggle + terminal button
            HStack(spacing: 2) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Button(action: {
                        if isFullTerminal { isFullTerminal = false }
                        viewMode = mode
                    }) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12))
                            .frame(width: 28, height: 22)
                            .background(
                                viewMode == mode && !isFullTerminal
                                    ? Color.white.opacity(0.15)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(viewMode == mode && !isFullTerminal ? .white : .white.opacity(0.4))
                    .help(mode.label)
                }

                // Terminal toggle button (part of the mode group)
                Button(action: {
                    if isFullTerminal {
                        // Exit full terminal → show as bottom panel
                        isFullTerminal = false
                        showBottomTerminal = true
                    } else {
                        showBottomTerminal.toggle()
                    }
                }) {
                    Image(systemName: "terminal")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 22)
                        .background(
                            (showBottomTerminal || isFullTerminal)
                                ? Color.orange.opacity(0.2)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .foregroundStyle((showBottomTerminal || isFullTerminal) ? .orange : .white.opacity(0.4))
                .help(showBottomTerminal ? "터미널 닫기" : "터미널 열기")
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

// MARK: - Bottom Terminal Panel

struct BottomTerminalPanel: View {
    @EnvironmentObject var terminalManager: TerminalManager
    @EnvironmentObject var noteStore: NoteStore
    @Binding var height: CGFloat
    @Binding var showBottomTerminal: Bool
    @Binding var isFullTerminal: Bool
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle / header
            HStack(spacing: 8) {
                // Drag handle
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(0.2))
                    .frame(width: 36, height: 3)

                Spacer()

                Text("터미널")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))

                if !terminalManager.sessions.isEmpty {
                    Text("\(terminalManager.sessions.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }

                Spacer()

                // Maximize — switch to full terminal view
                Button(action: {
                    showBottomTerminal = false
                    isFullTerminal = true
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("전체 터미널로 전환")

                // Close
                Button(action: { showBottomTerminal = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("터미널 패널 닫기")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.5))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let newHeight = height - value.translation.height
                        height = max(120, min(500, newHeight))
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }

            // Divider
            Rectangle()
                .fill(Color.orange.opacity(0.3))
                .frame(height: 1)

            // Terminal content — reuse TerminalContainerView
            TerminalContainerView()
        }
        .frame(height: height)
        .onAppear {
            if terminalManager.sessions.isEmpty {
                let dir = noteStore.selectedProject?.path ?? NSHomeDirectory()
                terminalManager.createSession(workingDirectory: dir)
            }
        }
    }
}
