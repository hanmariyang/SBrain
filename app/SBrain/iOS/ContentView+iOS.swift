import SwiftUI

// MARK: - iOS Tab-Based Content View

struct IOSContentView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var syncManager: SyncManager
    @EnvironmentObject var slackStore: SlackStore
    @EnvironmentObject var calendarStore: CalendarStore

    @State private var selectedTab: IOSTab = .brain

    enum IOSTab: String, CaseIterable {
        case brain = "Brain Map"
        case notes = "Notes"
        case search = "Search"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .brain: return "brain"
            case .notes: return "doc.text"
            case .search: return "magnifyingglass"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Brain Map
            NavigationStack {
                IOSBrainMapView()
                    .navigationTitle("Brain Map")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label(IOSTab.brain.rawValue, systemImage: IOSTab.brain.icon)
            }
            .tag(IOSTab.brain)

            // Tab 2: Notes
            NavigationStack {
                IOSNotesView()
                    .navigationTitle("Notes")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label(IOSTab.notes.rawValue, systemImage: IOSTab.notes.icon)
            }
            .tag(IOSTab.notes)

            // Tab 3: Search
            NavigationStack {
                IOSSearchView()
                    .navigationTitle("Recall")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label(IOSTab.search.rawValue, systemImage: IOSTab.search.icon)
            }
            .tag(IOSTab.search)

            // Tab 4: Settings
            NavigationStack {
                IOSSettingsView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label(IOSTab.settings.rawValue, systemImage: IOSTab.settings.icon)
            }
            .tag(IOSTab.settings)
        }
        .tint(SB.Colors.gold600)
        .task {
            // iOS: Railway API에서 노트 로드
            await noteStore.loadCloudNotes()
        }
    }
}

// MARK: - Notes Tab (Cloud Notes from Railway API)

struct IOSNotesView: View {
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        Group {
            if noteStore.isLoadingCloud {
                ProgressView("Loading notes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if noteStore.cloudNotes.isEmpty {
                ContentUnavailableView(
                    "No Notes",
                    systemImage: "brain",
                    description: Text("Sync notes from macOS app first.\nSettings > Cloud Sync > Connect")
                )
            } else {
                List(noteStore.cloudNotes) { note in
                    NavigationLink(value: note.id) {
                        IOSNoteRow(note: note)
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await noteStore.loadCloudNotes()
                }
            }
        }
        .navigationDestination(for: String.self) { noteId in
            IOSCloudNoteDetailView(noteId: noteId)
        }
    }
}

/// Railway API에서 가져온 노트 상세 뷰
struct IOSCloudNoteDetailView: View {
    let noteId: String
    @EnvironmentObject var noteStore: NoteStore
    @State private var content: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let content = content {
                IOSMarkdownWebView(markdown: content)
            } else {
                ContentUnavailableView("Failed to load", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(noteStore.cloudNotes.first(where: { $0.id == noteId })?.filename ?? "Note")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            content = await noteStore.loadCloudNoteContent(id: noteId)
            isLoading = false
        }
    }
}

struct IOSNoteRow: View {
    let note: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: SB.Space.sm) {
                Image(systemName: fileIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(SB.Colors.accentBlue)

                Text((note.filename as NSString).deletingPathExtension)
                    .font(SB.Font.bodyMd())
                    .foregroundStyle(SB.Colors.navy900)
                    .lineLimit(1)

                Spacer()

                Text(note.path.components(separatedBy: "/").first ?? "")
                    .font(SB.Font.monoSm())
                    .foregroundStyle(SB.Colors.navy300)
            }

            if let preview = note.preview, !preview.isEmpty {
                Text(preview)
                    .font(SB.Font.bodySm())
                    .foregroundStyle(SB.Colors.navy500)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var fileIcon: String {
        let ext = (note.filename as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "globe"
        case "md", "markdown": return "doc.text"
        default: return "doc"
        }
    }
}

// MARK: - Search Tab

struct IOSSearchView: View {
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: SB.Space.sm) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(noteStore.isSearchActive ? SB.Colors.gold600 : SB.Colors.navy300)
                    .font(.system(size: 14))

                TextField("Recall...", text: $noteStore.searchQuery)
                    .font(SB.Font.bodyMd())
                    .foregroundStyle(SB.Colors.navy900)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await noteStore.recallFromCloud() }
                    }

                if noteStore.isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(SB.Colors.gold600)
                }

                if !noteStore.searchQuery.isEmpty {
                    Button(action: { noteStore.clearSearch() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SB.Colors.navy300)
                    }
                }
            }
            .padding(SB.Space.md)
            .background(SB.Colors.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: SB.Radius.md))
            .padding(.horizontal, SB.Space.lg)
            .padding(.top, SB.Space.sm)

            if let error = noteStore.searchError {
                Text(error)
                    .font(SB.Font.bodySm())
                    .foregroundStyle(SB.Colors.accentRed)
                    .padding(.top, SB.Space.sm)
            }

            // Results
            if noteStore.filteredSearchResults.isEmpty && noteStore.isSearchActive {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No notes matched your query.")
                )
            } else if noteStore.filteredSearchResults.isEmpty {
                ContentUnavailableView(
                    "Search Memories",
                    systemImage: "brain.head.profile",
                    description: Text("Enter a query to recall related notes.")
                )
            } else {
                List(noteStore.filteredSearchResults) { result in
                    NavigationLink(value: result.noteId) {
                        IOSSearchResultRow(result: result)
                    }
                }
                .listStyle(.plain)
                .navigationDestination(for: String.self) { noteId in
                    IOSCloudNoteDetailView(noteId: noteId)
                }
            }
        }
        .background(SB.Colors.bgPrimary)
    }
}

struct IOSSearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: SB.Space.sm) {
                // Score indicator
                Circle()
                    .fill(SB.Colors.gold600.opacity(result.score))
                    .frame(width: 8, height: 8)

                Text((result.filename as NSString).deletingPathExtension)
                    .font(SB.Font.bodyMd())
                    .foregroundStyle(SB.Colors.navy900)
                    .lineLimit(1)

                Spacer()

                Text("\(Int(result.score * 100))%")
                    .font(SB.Font.monoSm())
                    .foregroundStyle(SB.Colors.gold600)
            }

            if !result.chunkText.isEmpty {
                Text(result.chunkText)
                    .font(SB.Font.bodySm())
                    .foregroundStyle(SB.Colors.navy500)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Settings Tab

struct IOSSettingsView: View {
    @EnvironmentObject var syncManager: SyncManager
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var slackStore: SlackStore
    @EnvironmentObject var calendarStore: CalendarStore

    var body: some View {
        List {
            // Cloud connection
            Section("Cloud Connection") {
                HStack {
                    Label("Status", systemImage: "cloud")
                    Spacer()
                    HStack(spacing: SB.Space.xs) {
                        Circle()
                            .fill(syncManager.isCloudAuthenticated ? SB.Colors.accentGreen : SB.Colors.accentRed)
                            .frame(width: 8, height: 8)
                        Text(syncManager.isCloudAuthenticated ? "Connected" : "Disconnected")
                            .font(SB.Font.monoSm())
                            .foregroundStyle(SB.Colors.navy500)
                    }
                }

                if let lastSync = syncManager.lastSyncAt {
                    HStack {
                        Label("Last Sync", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Text(lastSync, style: .relative)
                            .font(SB.Font.monoSm())
                            .foregroundStyle(SB.Colors.navy500)
                    }
                }

                if syncManager.isSyncing {
                    HStack {
                        Label("Syncing...", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }

            // Integrations
            Section("Integrations") {
                HStack {
                    Label("Slack", systemImage: "number.square")
                    Spacer()
                    HStack(spacing: SB.Space.xs) {
                        Circle()
                            .fill(slackStore.isConnected ? SB.Colors.accentGreen : SB.Colors.accentRed)
                            .frame(width: 8, height: 8)
                        Text(slackStore.isConnected ? "Connected" : "Disconnected")
                            .font(SB.Font.monoSm())
                            .foregroundStyle(SB.Colors.navy500)
                    }
                }

                HStack {
                    Label("Calendar", systemImage: "calendar")
                    Spacer()
                    HStack(spacing: SB.Space.xs) {
                        Circle()
                            .fill(calendarStore.isAuthenticated ? SB.Colors.accentGreen : SB.Colors.accentRed)
                            .frame(width: 8, height: 8)
                        Text(calendarStore.isAuthenticated ? "Authenticated" : "Not connected")
                            .font(SB.Font.monoSm())
                            .foregroundStyle(SB.Colors.navy500)
                    }
                }
            }

            // Cache
            Section("Data") {
                HStack {
                    Label("Projects", systemImage: "folder")
                    Spacer()
                    Text("\(noteStore.projects.count)")
                        .font(SB.Font.monoSm())
                        .foregroundStyle(SB.Colors.navy500)
                }

                HStack {
                    Label("Total Files", systemImage: "doc.text")
                    Spacer()
                    Text("\(noteStore.totalDocCount)")
                        .font(SB.Font.monoSm())
                        .foregroundStyle(SB.Colors.navy500)
                }
            }

            // App info
            Section("App Info") {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                        .font(SB.Font.monoSm())
                        .foregroundStyle(SB.Colors.navy500)
                }

                HStack {
                    Label("Build", systemImage: "hammer")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-")
                        .font(SB.Font.monoSm())
                        .foregroundStyle(SB.Colors.navy500)
                }
            }

            // Logout
            Section {
                Button(role: .destructive) {
                    syncManager.logout()
                } label: {
                    HStack {
                        Spacer()
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
