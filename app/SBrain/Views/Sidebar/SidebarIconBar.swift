import SwiftUI

// MARK: - Sidebar Icon Bar (48px, leftmost column)

struct SidebarIconBar: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var backendManager: BackendManager
    @Binding var viewMode: ViewMode
    @Binding var showBottomTerminal: Bool
    @Binding var isFullTerminal: Bool
    @Binding var showExplorerPanel: Bool
    @Binding var isSearchMode: Bool

    var body: some View {
        VStack(spacing: 0) {
            // ── Top: Logo + Projects ──
            VStack(spacing: SB.Space.sm) {
                // SB Logo → "All projects"
                Button(action: { noteStore.selectProject(nil) }) {
                    Text("SB")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(noteStore.selectedProjectId == nil ? SB.Colors.iconBarActive : SB.Colors.iconBarIcon)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: SB.Radius.sm)
                                .fill(noteStore.selectedProjectId == nil ? SB.Colors.iconBarActive.opacity(0.2) : Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help("전체 프로젝트")

                // Base folder (내 기억)
                if let baseProject = noteStore.projects.first(where: { $0.isBaseFolder }) {
                    IconBarProjectButton(
                        project: baseProject,
                        isActive: noteStore.selectedProjectId == baseProject.id,
                        icon: "brain.head.profile"
                    ) {
                        noteStore.selectProject(baseProject.id)
                    }
                }

                // Other projects
                ForEach(noteStore.projects.filter { !$0.isBaseFolder }, id: \.id) { project in
                    IconBarProjectButton(
                        project: project,
                        isActive: noteStore.selectedProjectId == project.id
                    ) {
                        noteStore.selectProject(project.id)
                    }
                }

                // Add project
                Button(action: { noteStore.addFolder() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: SB.Radius.sm))
                }
                .buttonStyle(.plain)
                .help("프로젝트 추가")
            }
            .padding(.top, SB.Space.md)

            Spacer()

            // ── Middle: Search ──
            iconBarDivider

            IconBarButton(icon: "magnifyingglass", isActive: isSearchMode) {
                isSearchMode.toggle()
                if isSearchMode && !showExplorerPanel {
                    showExplorerPanel = true
                }
            }
            .help("검색 (회상)")

            // ── Bottom: View modes + Terminal ──
            iconBarDivider

            VStack(spacing: 2) {
                IconBarButton(icon: "list.bullet", isActive: viewMode == .list && !isFullTerminal) {
                    isFullTerminal = false
                    viewMode = .list
                }
                .help("리스트 뷰")

                IconBarButton(icon: "brain", isActive: viewMode == .brain && !isFullTerminal) {
                    isFullTerminal = false
                    viewMode = .brain
                }
                .help("Brain Map")

                IconBarButton(icon: "cylinder.split.1x2", isActive: viewMode == .database && !isFullTerminal) {
                    isFullTerminal = false
                    viewMode = .database
                }
                .help("데이터베이스")

                IconBarButton(icon: "terminal", isActive: showBottomTerminal || isFullTerminal) {
                    if isFullTerminal {
                        isFullTerminal = false
                        showBottomTerminal = true
                    } else {
                        showBottomTerminal.toggle()
                    }
                }
                .help("터미널")
            }
            .padding(.vertical, SB.Space.sm)

            iconBarDivider

            // ── Bottommost: Explorer toggle + Settings ──
            VStack(spacing: 2) {
                IconBarButton(icon: "sidebar.left", isActive: showExplorerPanel) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showExplorerPanel.toggle()
                    }
                }
                .help(showExplorerPanel ? "탐색 패널 닫기" : "탐색 패널 열기")

                IconBarButton(icon: "gearshape", isActive: false) {
                    // TODO: settings
                }
                .help("설정")
            }
            .padding(.bottom, SB.Space.md)
        }
        .frame(width: SB.Layout.iconBarWidth)
        .background(SB.Colors.iconBarBg)
    }

    private var iconBarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(height: 1)
            .padding(.horizontal, SB.Space.sm)
            .padding(.vertical, SB.Space.xs)
    }
}

// MARK: - Icon Bar Button (for dark navy background)

struct IconBarButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isActive ? SB.Colors.iconBarActive : SB.Colors.iconBarIcon)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: SB.Radius.sm)
                        .fill(isActive ? SB.Colors.iconBarActive.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Icon Bar Project Button

struct IconBarProjectButton: View {
    let project: ProjectFolder
    let isActive: Bool
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isActive ? SB.Colors.iconBarActive : SB.Colors.iconBarIcon)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: SB.Radius.sm)
                            .fill(isActive ? projectColor.opacity(0.2) : Color.white.opacity(0.06))
                    )
            } else {
                Text(projectInitial)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isActive ? .white : SB.Colors.iconBarIcon)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isActive ? projectColor : projectColor.opacity(0.3))
                    )
            }
        }
        .buttonStyle(.plain)
        .help(project.name)
    }

    private var projectInitial: String {
        String(project.name.prefix(1)).uppercased()
    }

    private var projectColor: Color {
        let hash = abs(project.path.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.5, brightness: 0.7)
    }
}
