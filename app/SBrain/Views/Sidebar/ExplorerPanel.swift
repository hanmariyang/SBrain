import SwiftUI

// MARK: - Explorer Panel (240px, collapsible)

struct ExplorerPanel: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var dbStore: DatabaseStore
    @Binding var viewMode: ViewMode
    @Binding var isSearchMode: Bool

    var body: some View {
        VStack(spacing: 0) {
            explorerHeader

            Rectangle()
                .fill(SB.Colors.navy100)
                .frame(height: 1)

            if isSearchMode || noteStore.isSearchActive {
                ExplorerSearchView(isSearchMode: $isSearchMode)
            } else if viewMode == .calendar {
                CalendarExplorerView()
            } else if viewMode == .slack {
                SlackExplorerView()
            } else if viewMode == .database {
                DatabaseExplorerView()
            } else {
                ExplorerFileTree()
            }
        }
        .background(SB.Colors.bgSecondary)
    }

    private var explorerHeader: some View {
        HStack(spacing: SB.Space.sm) {
            Image(systemName: headerIcon)
                .font(.system(size: 11))
                .foregroundStyle(SB.Colors.navy500)

            Text(headerTitle)
                .font(SB.Font.caption())
                .foregroundStyle(SB.Colors.navy500)
                .textCase(.uppercase)

            Spacer()

            if noteStore.hasProjects && !isSearchMode {
                Text("\(noteStore.totalDocCount)")
                    .font(SB.Font.monoSm())
                    .foregroundStyle(SB.Colors.navy300)
            }

            // New file button (when base folder is selected)
            if let sel = noteStore.selectedProjectId,
               noteStore.projects.first(where: { $0.id == sel })?.isBaseFolder == true,
               !isSearchMode {
                NewFileButton()
            }
        }
        .padding(.horizontal, SB.Space.md)
        .padding(.vertical, SB.Space.sm)
    }

    private var headerIcon: String {
        if isSearchMode || noteStore.isSearchActive { return "magnifyingglass" }
        switch viewMode {
        case .list, .brain: return "folder"
        case .database: return "cylinder.split.1x2"
        case .calendar: return "calendar"
        case .slack: return "number.square"
        }
    }

    private var headerTitle: String {
        if isSearchMode || noteStore.isSearchActive { return "검색 결과" }
        switch viewMode {
        case .list, .brain: return "탐색기"
        case .database: return "데이터베이스"
        case .calendar: return "캘린더"
        case .slack: return "슬랙"
        }
    }
}

// MARK: - New File Button

private struct NewFileButton: View {
    @State private var showNewFileDialog = false

    var body: some View {
        Button(action: { showNewFileDialog = true }) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 10))
                .foregroundStyle(SB.Colors.accentGreen)
        }
        .buttonStyle(.plain)
        .help("새 문서 만들기")
        .sheet(isPresented: $showNewFileDialog) {
            NewFileDialog(isPresented: $showNewFileDialog)
        }
    }
}

// MARK: - New File Dialog

struct NewFileDialog: View {
    @EnvironmentObject var noteStore: NoteStore
    @Binding var isPresented: Bool
    @State private var fileName = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: SB.Space.lg) {
            Text("새 문서 만들기")
                .font(SB.Font.titleSm())
                .foregroundStyle(SB.Colors.navy900)

            TextField("파일명 (예: my-note.md)", text: $fileName)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { create() }

            HStack(spacing: SB.Space.md) {
                Button("취소") { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Button("만들기") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(fileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(SB.Space.xl)
        .frame(width: 320)
        .onAppear { isFocused = true }
    }

    private func create() {
        if noteStore.createNewFile(name: fileName) != nil {
            isPresented = false
        }
    }
}

// MARK: - Explorer File Tree

struct ExplorerFileTree: View {
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        ScrollView {
            if noteStore.hasProjects {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(noteStore.visibleProjects) { project in
                        if let root = project.rootFolder {
                            ExplorerProjectHeader(project: project)

                            ForEach(root.children) { node in
                                ExplorerNodeRow(node: node, depth: 1)
                            }
                        }
                    }
                }
                .padding(.vertical, SB.Space.xs)
            } else {
                explorerEmptyState
            }
        }
    }

    private var explorerEmptyState: some View {
        VStack(spacing: SB.Space.md) {
            Spacer().frame(height: SB.Space.xxl)

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(SB.Colors.navy300)

            Text("프로젝트를 추가하세요")
                .font(SB.Font.bodySm())
                .foregroundStyle(SB.Colors.navy500)

            Button(action: { noteStore.addFolder() }) {
                Label("프로젝트 추가", systemImage: "plus")
                    .font(SB.Font.bodySm())
            }
            .buttonStyle(SBGoldButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(SB.Space.lg)
    }
}

// MARK: - Explorer Project Header

struct ExplorerProjectHeader: View {
    let project: ProjectFolder

    var body: some View {
        HStack(spacing: SB.Space.sm) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(projectColor)

            Text(project.name)
                .font(SB.Font.titleSm())
                .foregroundStyle(SB.Colors.navy900)

            if let root = project.rootFolder {
                Text("\(root.docFileCount)")
                    .font(SB.Font.monoSm())
                    .foregroundStyle(SB.Colors.navy300)
            }

            Spacer()
        }
        .padding(.horizontal, SB.Space.md)
        .padding(.vertical, SB.Space.sm)
        .background(SB.Colors.bgTertiary.opacity(0.5))
    }

    private var projectColor: Color {
        let hash = abs(project.path.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.5, brightness: 0.65)
    }
}

// MARK: - Explorer Node Row (Folder/File)

struct ExplorerNodeRow: View {
    @EnvironmentObject var noteStore: NoteStore
    let node: FolderNode
    let depth: Int
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if node.isFolder {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                }) {
                    HStack(spacing: SB.Space.xs) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(SB.Colors.navy300)
                            .frame(width: 12)

                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 11))
                            .foregroundStyle(SB.Colors.gold600.opacity(0.7))

                        Text(node.name)
                            .font(SB.Font.bodySm())
                            .foregroundStyle(SB.Colors.navy700)

                        Text("\(node.docFileCount)")
                            .font(SB.Font.monoSm())
                            .foregroundStyle(SB.Colors.navy300)

                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 14 + 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ForEach(node.children) { child in
                        ExplorerNodeRow(node: child, depth: depth + 1)
                    }
                }
            } else {
                ExplorerFileRow(node: node, depth: depth)
            }
        }
    }
}

// MARK: - Explorer File Row

struct ExplorerFileRow: View {
    @EnvironmentObject var noteStore: NoteStore
    let node: FolderNode
    let depth: Int
    @State private var isHovered = false

    private var isSelected: Bool {
        noteStore.selectedFilePath == node.path
    }

    var body: some View {
        Button(action: { noteStore.selectFile(path: node.path) }) {
            HStack(spacing: SB.Space.sm) {
                Image(systemName: fileIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(fileIconColor)
                    .frame(width: 14)

                Text((node.name as NSString).deletingPathExtension)
                    .font(SB.Font.bodySm())
                    .foregroundStyle(isSelected ? SB.Colors.navy900 : SB.Colors.navy700)
                    .lineLimit(1)

                Text(fileExtension.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(fileIconColor.opacity(0.8))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(fileIconColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 14 + 20)
            .padding(.trailing, SB.Space.sm)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: SB.Radius.sm)
                    .fill(isSelected ? SB.Colors.gold100 : (isHovered ? SB.Colors.bgTertiary : Color.clear))
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var fileExtension: String {
        (node.name as NSString).pathExtension.lowercased()
    }

    private var fileIcon: String {
        switch fileExtension {
        case "html", "htm": return "globe"
        case "md", "markdown": return "doc.text"
        case "txt": return "doc.plaintext"
        case "json": return "curlybraces"
        case "yaml", "yml": return "list.bullet.indent"
        case "csv": return "tablecells"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }

    private var fileIconColor: Color {
        switch fileExtension {
        case "html", "htm": return SB.Colors.accentOrange
        case "md", "markdown": return SB.Colors.accentBlue
        case "txt": return SB.Colors.navy500
        case "json": return SB.Colors.gold600
        case "yaml", "yml": return SB.Colors.accentGreen
        case "csv": return SB.Colors.accentBlue
        case "pdf": return SB.Colors.accentRed
        default: return SB.Colors.navy500
        }
    }
}

// MARK: - Explorer Search View

struct ExplorerSearchView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Binding var isSearchMode: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search input
            HStack(spacing: SB.Space.sm) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(noteStore.isSearchActive ? SB.Colors.gold600 : SB.Colors.navy500)

                TextField("회상하기...", text: $noteStore.searchQuery)
                    .textFieldStyle(.plain)
                    .font(SB.Font.bodyMd())
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
                    Button(action: {
                        noteStore.clearSearch()
                        isSearchMode = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(SB.Colors.navy300)
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
            .padding(.vertical, SB.Space.sm)
            .background(noteStore.isSearchActive ? SB.Colors.gold100.opacity(0.3) : SB.Colors.bgTertiary.opacity(0.5))

            // Error message
            if let error = noteStore.searchError, !noteStore.isSearching {
                Text(error)
                    .font(SB.Font.caption())
                    .foregroundStyle(SB.Colors.accentRed)
                    .padding(.horizontal, SB.Space.md)
                    .padding(.vertical, SB.Space.xs)
            }

            // Results
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(noteStore.filteredSearchResults) { result in
                        ExplorerSearchResultRow(result: result)
                    }
                }
                .padding(.vertical, SB.Space.xs)
            }
        }
    }
}

// MARK: - Explorer Search Result Row

struct ExplorerSearchResultRow: View {
    @EnvironmentObject var noteStore: NoteStore
    let result: SearchResult
    @State private var isHovered = false

    private var isSelected: Bool {
        noteStore.selectedFilePath == result.path
    }

    var body: some View {
        Button(action: { noteStore.selectFile(path: result.path) }) {
            HStack(spacing: SB.Space.sm) {
                Circle()
                    .fill(SB.Colors.gold600.opacity(0.3 + result.score * 0.7))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text((result.filename as NSString).deletingPathExtension)
                        .font(SB.Font.bodySm())
                        .foregroundStyle(SB.Colors.navy900)
                        .lineLimit(1)

                    Text(result.chunkText)
                        .font(SB.Font.caption())
                        .foregroundStyle(SB.Colors.navy500)
                        .lineLimit(2)
                }

                Spacer()

                Text("\(Int(result.score * 100))%")
                    .font(SB.Font.monoSm())
                    .foregroundStyle(SB.Colors.gold600)
            }
            .padding(.horizontal, SB.Space.md)
            .padding(.vertical, SB.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: SB.Radius.sm)
                    .fill(isSelected ? SB.Colors.gold100 : (isHovered ? SB.Colors.bgTertiary : Color.clear))
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Database Explorer View (table list in sidebar)

struct DatabaseExplorerView: View {
    @EnvironmentObject var dbStore: DatabaseStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !dbStore.isConnected {
                    VStack(spacing: SB.Space.md) {
                        Spacer().frame(height: SB.Space.xxl)
                        Image(systemName: "cylinder.split.1x2")
                            .font(.system(size: 28))
                            .foregroundStyle(SB.Colors.navy300)
                        Text("DB에 연결되지 않음")
                            .font(SB.Font.bodySm())
                            .foregroundStyle(SB.Colors.navy500)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    // Schema tabs
                    if dbStore.schemas.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SB.Space.xs) {
                                ForEach(dbStore.schemas) { schema in
                                    Button(action: { Task { await dbStore.selectSchema(schema.name) } }) {
                                        Text(schema.name)
                                            .font(SB.Font.caption())
                                            .foregroundStyle(dbStore.selectedSchema == schema.name ? SB.Colors.gold600 : SB.Colors.navy500)
                                            .padding(.horizontal, SB.Space.sm)
                                            .padding(.vertical, SB.Space.xs)
                                            .background(
                                                Capsule()
                                                    .fill(dbStore.selectedSchema == schema.name ? SB.Colors.gold100 : Color.clear)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, SB.Space.md)
                            .padding(.vertical, SB.Space.sm)
                        }
                    }

                    // Table list
                    ForEach(dbStore.tables, id: \.name) { table in
                        Button(action: { Task { await dbStore.selectTable(table) } }) {
                            HStack(spacing: SB.Space.sm) {
                                Image(systemName: "tablecells")
                                    .font(.system(size: 11))
                                    .foregroundStyle(SB.Colors.accentGreen)

                                Text(table.name)
                                    .font(SB.Font.bodySm())
                                    .foregroundStyle(SB.Colors.navy700)
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, SB.Space.md)
                            .padding(.vertical, SB.Space.xs + 2)
                            .background(
                                dbStore.selectedTable?.name == table.name
                                    ? SB.Colors.gold100
                                    : Color.clear
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
