import SwiftUI

enum ViewMode: String, CaseIterable {
    case brain = "brain"
    case list = "list"
    case database = "database"
    case calendar = "calendar"
    case slack = "slack"

    var icon: String {
        switch self {
        case .brain: return "brain"
        case .list: return "list.bullet"
        case .database: return "cylinder.split.1x2"
        case .calendar: return "calendar"
        case .slack: return "number.square"
        }
    }

    var label: String {
        switch self {
        case .brain: return "Brain Map"
        case .list: return "List"
        case .database: return "Database"
        case .calendar: return "캘린더"
        case .slack: return "슬랙"
        }
    }
}

// MARK: - Main Content View (2-Tier Sidebar Layout)

struct ContentView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var backendManager: BackendManager
    @EnvironmentObject var dbStore: DatabaseStore
    @EnvironmentObject var terminalManager: TerminalManager
    @EnvironmentObject var slackStore: SlackStore
    @EnvironmentObject var calendarStore: CalendarStore
    @EnvironmentObject var fileMonitor: FileMonitor
    @EnvironmentObject var syncManager: SyncManager

    @State private var viewMode: ViewMode = .list
    @State private var showExplorerPanel = true
    @State private var showBottomTerminal = false
    @State private var bottomTerminalHeight: CGFloat = SB.Layout.terminalDefaultHeight
    @State private var isFullTerminal = false
    @State private var isSearchMode = false

    var body: some View {
        HStack(spacing: 0) {
            // ── 1. Icon Bar (48px, always visible) ──
            SidebarIconBar(
                viewMode: $viewMode,
                showBottomTerminal: $showBottomTerminal,
                isFullTerminal: $isFullTerminal,
                showExplorerPanel: $showExplorerPanel,
                isSearchMode: $isSearchMode
            )

            // ── 2. Explorer Panel (collapsible) ──
            if showExplorerPanel {
                ExplorerPanel(
                    viewMode: $viewMode,
                    isSearchMode: $isSearchMode
                )
                .frame(
                    minWidth: SB.Layout.explorerPanelMinWidth,
                    idealWidth: SB.Layout.explorerPanelWidth,
                    maxWidth: SB.Layout.explorerPanelMaxWidth
                )

                // Vertical divider
                Rectangle()
                    .fill(SB.Colors.navy100)
                    .frame(width: 1)
            }

            // ── 3. Main Content Area ──
            VStack(spacing: 0) {
                // Simplified Top Bar
                MainTopBar(viewMode: viewMode)

                // Ingestion progress
                if noteStore.isIngesting, let status = noteStore.ingestStatus {
                    MemorizeProgressView(status: status)
                }

                // Content
                if isFullTerminal {
                    TerminalContainerView()
                } else {
                    mainContentView
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
            }
            .background(SB.Colors.bgPrimary)
        }
        .frame(minWidth: 900, minHeight: 550)
        .onChange(of: backendManager.isRunning) { _, isRunning in
            guard isRunning else { return }
            Task {
                // Phase 1: 프로젝트 복원
                noteStore.restoreProjects()

                // Phase 2: 인증 상태 복원 (병렬)
                async let calAuth: () = calendarStore.checkAuth()
                async let slkAuth: () = slackStore.checkStatus()
                _ = await (calAuth, slkAuth)

                // Phase 3: 파일 모니터 시작
                fileMonitor.onFilesChanged = { [weak noteStore] paths in
                    noteStore?.handleFileChange(changedPaths: paths)
                }
                for project in noteStore.projects {
                    fileMonitor.startWatching(path: project.path)
                }

                // Phase 4: 클라우드 초기 동기화
                await syncManager.fullSync(projects: noteStore.projects)
            }
        }
        .onChange(of: dbStore.dbBrainGraph?.neurons.count) { _, _ in
            noteStore.dbBrainGraph = dbStore.dbBrainGraph
        }
    }

    // MARK: - Main Content (varies by view mode)

    @ViewBuilder
    private var mainContentView: some View {
        if !noteStore.hasProjects && viewMode != .database && viewMode != .calendar && viewMode != .slack {
            emptyState
        } else {
            switch viewMode {
            case .brain:
                HSplitView {
                    BrainMapView()
                        .frame(minWidth: 300)
                    if noteStore.selectedFilePath != nil {
                        detailView
                            .frame(minWidth: 300, idealWidth: 400)
                    }
                }
            case .list:
                detailView
            case .database:
                if dbStore.isConnected {
                    DBDetailView()
                } else {
                    DatabaseBrowserView()
                }
            case .calendar:
                CalendarView()
            case .slack:
                SlackAgentView()
            }
        }
    }

    // MARK: - Detail View (list mode + brain mode DB navigation)

    @ViewBuilder
    private var detailView: some View {
        if viewMode == .brain,
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
        let stripped = String(path.dropFirst(3))
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: SB.Space.lg) {
            Spacer()

            Image(systemName: "brain")
                .font(.system(size: 64))
                .foregroundStyle(
                    .linearGradient(
                        colors: [SB.Colors.navy700, SB.Colors.gold600],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.4)

            Text("프로젝트를 추가하세요")
                .font(SB.Font.titleMd())
                .foregroundStyle(SB.Colors.navy500)

            Text("여러 프로젝트 폴더를 추가하면\n하나의 Brain Map에서 통합 탐색할 수 있습니다")
                .font(SB.Font.bodySm())
                .foregroundStyle(SB.Colors.navy300)
                .multilineTextAlignment(.center)

            Button(action: { noteStore.addFolder() }) {
                Label("프로젝트 추가", systemImage: "folder.badge.plus")
            }
            .buttonStyle(SBGoldButtonStyle())

            Spacer()
        }
    }
}

// MARK: - Simplified Top Bar

struct MainTopBar: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var backendManager: BackendManager
    @EnvironmentObject var handTracking: HandTrackingManager
    let viewMode: ViewMode

    var body: some View {
        HStack(spacing: SB.Space.md) {
            // Left: SBrain + project info
            HStack(spacing: SB.Space.sm) {
                Circle()
                    .fill(backendManager.isRunning ? SB.Colors.accentGreen : SB.Colors.accentRed)
                    .frame(width: 7, height: 7)

                Text("SBrain")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [SB.Colors.navy700, SB.Colors.gold600],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                // Breadcrumb
                if let project = noteStore.selectedProject {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(SB.Colors.navy300)
                    Text(project.name)
                        .font(SB.Font.bodySm())
                        .foregroundStyle(SB.Colors.navy500)
                }
            }

            Spacer()

            // Center: Search bar
            RecallBar()

            Spacer()

            // Right: Status + controls
            if noteStore.hasProjects {
                Text("\(noteStore.projects.count) projects · \(noteStore.totalDocCount) files")
                    .font(SB.Font.monoSm())
                    .foregroundStyle(SB.Colors.navy300)
            }

            // Hand tracking toggle
            Button(action: { handTracking.isEnabled.toggle() }) {
                Image(systemName: handTracking.isEnabled ? "hand.raised.fill" : "hand.raised")
                    .font(.system(size: 11))
                    .padding(5)
                    .background(handTracking.isEnabled
                        ? (handTracking.isTracking ? SB.Colors.accentGreen.opacity(0.15) : SB.Colors.accentOrange.opacity(0.15))
                        : SB.Colors.bgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: SB.Radius.sm))
            }
            .buttonStyle(.plain)
            .foregroundStyle(handTracking.isEnabled
                ? (handTracking.isTracking ? SB.Colors.accentGreen : SB.Colors.accentOrange)
                : SB.Colors.navy500)
            .help(handTracking.isEnabled ? "손 추적 끄기" : "손 추적 켜기")
            .opacity(handTracking.cameraAuthorized ? 1 : 0.3)
            .disabled(!handTracking.cameraAuthorized && !handTracking.isEnabled)
        }
        .padding(.horizontal, SB.Space.lg)
        .padding(.vertical, SB.Space.sm)
        .frame(height: SB.Layout.topBarHeight)
        .background(SB.Colors.bgElevated)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SB.Colors.navy100).frame(height: 1)
        }
    }
}

// MARK: - Recall Bar (Search in Top Bar)

struct RecallBar: View {
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        HStack(spacing: SB.Space.sm) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(noteStore.isSearchActive ? SB.Colors.gold600 : SB.Colors.navy300)
                .font(.system(size: 11))

            TextField("회상하기...", text: $noteStore.searchQuery)
                .textFieldStyle(.plain)
                .font(SB.Font.bodySm())
                .foregroundStyle(SB.Colors.navy900)
                .onSubmit {
                    Task { await noteStore.recall() }
                }

            if noteStore.isSearchActive {
                Text("\(noteStore.filteredSearchResults.count)")
                    .font(SB.Font.monoSm())
                    .foregroundStyle(SB.Colors.gold600)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(SB.Colors.gold100)
                    .clipShape(Capsule())
            }

            if !noteStore.searchQuery.isEmpty {
                Button(action: { noteStore.clearSearch() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SB.Colors.navy300)
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }

            if noteStore.isSearching {
                ProgressView()
                    .scaleEffect(0.5)
                    .tint(SB.Colors.gold600)
            }
        }
        .padding(.horizontal, SB.Space.md)
        .padding(.vertical, SB.Space.xs + 2)
        .background(noteStore.isSearchActive ? SB.Colors.gold100.opacity(0.5) : SB.Colors.bgSecondary)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(SB.Colors.navy100, lineWidth: 1)
        )
        .frame(maxWidth: 280)
    }
}

// MARK: - Memorize Progress

struct MemorizeProgressView: View {
    let status: IngestStatus

    var body: some View {
        HStack(spacing: SB.Space.md) {
            Image(systemName: "brain")
                .foregroundStyle(SB.Colors.gold600)
                .font(.system(size: 12))
                .symbolEffect(.pulse)

            if status.total > 0 {
                ProgressView(value: Double(status.done), total: Double(status.total))
                    .tint(
                        LinearGradient(
                            colors: [SB.Colors.navy700, SB.Colors.gold600],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("\(status.done)/\(status.total)")
                    .font(SB.Font.monoSm())
                    .foregroundStyle(SB.Colors.navy500)
            } else {
                Text("뇌 활성화 중...")
                    .font(SB.Font.bodySm())
                    .foregroundStyle(SB.Colors.navy500)

                ProgressView()
                    .scaleEffect(0.5)
                    .tint(SB.Colors.gold600)
            }
        }
        .padding(.horizontal, SB.Space.lg)
        .padding(.vertical, SB.Space.sm)
        .background(SB.Colors.gold600.opacity(0.08))
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
            HStack(spacing: SB.Space.sm) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(SB.Colors.navy300)
                    .frame(width: 36, height: 3)

                Spacer()

                Text("터미널")
                    .font(SB.Font.caption())
                    .foregroundStyle(SB.Colors.navy500)

                if !terminalManager.sessions.isEmpty {
                    Text("\(terminalManager.sessions.count)")
                        .font(SB.Font.monoSm())
                        .foregroundStyle(SB.Colors.gold600)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(SB.Colors.gold100)
                        .clipShape(Capsule())
                }

                Spacer()

                // Maximize
                Button(action: {
                    showBottomTerminal = false
                    isFullTerminal = true
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9))
                        .foregroundStyle(SB.Colors.navy500)
                }
                .buttonStyle(.plain)
                .help("전체 터미널로 전환")

                // Close
                Button(action: { showBottomTerminal = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SB.Colors.navy500)
                }
                .buttonStyle(.plain)
                .help("터미널 패널 닫기")
            }
            .padding(.horizontal, SB.Space.md)
            .padding(.vertical, SB.Space.xs)
            .background(SB.Colors.bgSecondary)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let newHeight = height - value.translation.height
                        height = max(SB.Layout.terminalMinHeight, min(SB.Layout.terminalMaxHeight, newHeight))
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
                .fill(SB.Colors.gold600.opacity(0.3))
                .frame(height: 1)

            // Terminal content
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
