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
            // Left: Projects + content
            VStack(spacing: 0) {
                TopBar(viewMode: $viewMode)

                if noteStore.isIngesting, let status = noteStore.ingestStatus {
                    MemorizeProgressView(status: status)
                }

                if noteStore.hasProjects {
                    // Project tabs
                    ProjectTabBar()

                    switch viewMode {
                    case .list:
                        FolderTreeView()
                    case .brain:
                        BrainMapView()
                    }
                } else {
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
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            noteStore.restoreProjects()
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
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(projectColor)
                    .frame(width: 6, height: 6)

                Text(project.name)
                    .font(.system(size: 11, weight: isActive ? .bold : .medium))
                    .foregroundStyle(.white.opacity(isActive ? 0.95 : 0.7))
                    .lineLimit(1)

                if let root = project.rootFolder {
                    Text("\(root.docFileCount)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }

                if isHovered {
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
                            .stroke(isActive ? projectColor.opacity(0.5) : projectColor.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
