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
        .onAppear {
            // Fetch initial data from Railway API
            Task {
                async let calAuth: () = calendarStore.checkAuth()
                async let slkAuth: () = slackStore.checkStatus()
                _ = await (calAuth, slkAuth)
                await syncManager.fullSync(projects: noteStore.projects)
            }
        }
    }
}

// MARK: - Notes Tab (List + Detail)

struct IOSNotesView: View {
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        List {
            if noteStore.hasProjects {
                ForEach(noteStore.visibleProjects) { project in
                    if let root = project.rootFolder {
                        Section(header: IOSProjectHeader(project: project)) {
                            ForEach(flatFiles(root), id: \.path) { node in
                                NavigationLink(value: node.path) {
                                    IOSFileRow(node: node)
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "brain",
                    description: Text("Add projects from macOS app.\nNotes will sync via Railway Cloud.")
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: String.self) { path in
            IOSNoteDetailView(path: path)
        }
    }

    /// Flatten folder tree into a list of file nodes
    private func flatFiles(_ node: FolderNode) -> [FolderNode] {
        var result: [FolderNode] = []
        if !node.isFolder {
            result.append(node)
        }
        for child in node.children {
            result.append(contentsOf: flatFiles(child))
        }
        return result
    }
}

struct IOSProjectHeader: View {
    let project: ProjectFolder

    var body: some View {
        HStack(spacing: SB.Space.sm) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(SB.Colors.gold600)

            Text(project.name)
                .font(SB.Font.titleSm())
                .foregroundStyle(SB.Colors.navy900)

            if let root = project.rootFolder {
                Text("\(root.docFileCount) files")
                    .font(SB.Font.monoSm())
                    .foregroundStyle(SB.Colors.navy300)
            }
        }
    }
}

struct IOSFileRow: View {
    let node: FolderNode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: SB.Space.sm) {
                Image(systemName: fileIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(SB.Colors.accentBlue)

                Text((node.name as NSString).deletingPathExtension)
                    .font(SB.Font.bodyMd())
                    .foregroundStyle(SB.Colors.navy900)
                    .lineLimit(1)

                Spacer()

                if let date = node.modifiedAt {
                    Text(formatDate(date))
                        .font(SB.Font.monoSm())
                        .foregroundStyle(SB.Colors.navy300)
                }
            }

            if !node.preview.isEmpty {
                Text(node.preview)
                    .font(SB.Font.bodySm())
                    .foregroundStyle(SB.Colors.navy500)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var fileIcon: String {
        let ext = (node.name as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "globe"
        case "md", "markdown": return "doc.text"
        default: return "doc"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd"
        return fmt.string(from: date)
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
                        Task { await noteStore.recall() }
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
                    NavigationLink(value: result.path) {
                        IOSSearchResultRow(result: result)
                    }
                }
                .listStyle(.plain)
                .navigationDestination(for: String.self) { path in
                    IOSNoteDetailView(path: path)
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
