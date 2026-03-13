import SwiftUI

enum ViewMode: String, CaseIterable {
    case brain = "brain"
    case list = "list"

    var icon: String {
        switch self {
        case .brain: return "brain"
        case .list: return "list.bullet"
        }
    }

    var label: String {
        switch self {
        case .brain: return "Brain Map"
        case .list: return "List"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var backendManager: BackendManager
    @State private var viewMode: ViewMode = .list

    var body: some View {
        HSplitView {
            // Left: Folder tree sidebar
            VStack(spacing: 0) {
                TopBar(viewMode: $viewMode)

                if noteStore.isIngesting, let status = noteStore.ingestStatus {
                    MemorizeProgressView(status: status)
                }

                if noteStore.rootFolder != nil {
                    switch viewMode {
                    case .list:
                        FolderTreeView()
                    case .brain:
                        BrainMapView()
                    }
                } else {
                    // No folder selected
                    emptyState
                }
            }
            .frame(minWidth: 500)
            .background(Color(nsColor: NSColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1)))

            // Right: File preview
            MemoryDetailView()
                .frame(minWidth: 350, idealWidth: 450)
        }
        .frame(minWidth: 900, minHeight: 550)
        .preferredColorScheme(.dark)
        .task {
            // Wait for backend, then restore last folder
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            noteStore.restoreLastFolder()
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

            Text("폴더를 선택하세요")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.5))

            Text("마크다운 파일이 있는 폴더를 지정하면\n폴더 구조 그대로 모든 .md 파일을 보여줍니다")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)

            Button(action: { noteStore.selectFolder() }) {
                Label("폴더 열기", systemImage: "folder")
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

// MARK: - Top Bar

struct TopBar: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var backendManager: BackendManager
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

            if let root = noteStore.rootFolder {
                Text("\(root.mdFileCount) files")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer()

            // Recall (search)
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

            // Folder button
            Button(action: { noteStore.selectFolder() }) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 12))
                    .padding(6)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
            .help("폴더 변경")
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
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(.cyan.opacity(0.6))
                .font(.system(size: 12))

            TextField("회상하기...", text: $noteStore.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .onSubmit {
                    Task { await noteStore.recall() }
                }

            if !noteStore.searchQuery.isEmpty {
                Button(action: {
                    noteStore.searchQuery = ""
                    noteStore.searchResults = []
                }) {
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
        .background(.white.opacity(0.06))
        .clipShape(Capsule())
        .frame(maxWidth: 300)
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
