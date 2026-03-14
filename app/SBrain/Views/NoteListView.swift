import SwiftUI

// MARK: - Folder Tree View

struct FolderTreeView: View {
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        ScrollView {
            if noteStore.isSearchActive {
                RecallResultList()
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(noteStore.visibleProjects) { project in
                        if let root = project.rootFolder {
                            // Project header
                            ProjectSectionHeader(project: project)

                            ForEach(root.children) { node in
                                FolderNodeRow(node: node, depth: 1)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct ProjectSectionHeader: View {
    let project: ProjectFolder

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(projectColor)

            Text(project.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))

            if let root = project.rootFolder {
                Text("\(root.docFileCount)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
    }

    private var projectColor: Color {
        let hash = abs(project.path.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.8)
    }
}

// MARK: - Recursive Folder/File Row

struct FolderNodeRow: View {
    @EnvironmentObject var noteStore: NoteStore
    let node: FolderNode
    let depth: Int

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if node.isFolder {
                // Folder header
                Button(action: { withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.3))
                            .frame(width: 12)

                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 12))
                            .foregroundStyle(.cyan.opacity(0.6))

                        Text(node.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))

                        Text("\(node.docFileCount)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.2))

                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 16 + 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Children
                if isExpanded {
                    ForEach(node.children) { child in
                        FolderNodeRow(node: child, depth: depth + 1)
                    }
                }
            } else {
                // Markdown file row
                FileRow(node: node, depth: depth)
            }
        }
    }
}

// MARK: - File Row with Preview

struct FileRow: View {
    @EnvironmentObject var noteStore: NoteStore
    let node: FolderNode
    let depth: Int

    private var isSelected: Bool {
        noteStore.selectedFilePath == node.path
    }

    var body: some View {
        Button(action: { noteStore.selectFile(path: node.path) }) {
            HStack(alignment: .top, spacing: 8) {
                // Neuron indicator
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                isSelected ? Color.cyan : Color.purple.opacity(0.8),
                                isSelected ? Color.cyan.opacity(0.2) : Color.purple.opacity(0.15),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 5
                        )
                    )
                    .frame(width: 8, height: 8)
                    .shadow(color: isSelected ? .cyan.opacity(0.6) : .clear, radius: 4)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text((node.name as NSString).deletingPathExtension)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.8))
                        .lineLimit(1)

                    if !node.preview.isEmpty {
                        Text(node.preview)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                            .lineLimit(2)
                            .lineSpacing(1)
                    }
                }

                Spacer()

                if let date = node.modifiedAt {
                    Text(formatDate(date))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.15))
                        .padding(.top, 2)
                }
            }
            .padding(.leading, CGFloat(depth) * 16 + 20)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.cyan.opacity(0.1) : Color.clear)
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd"
        return fmt.string(from: date)
    }
}

// MARK: - Search Results

struct RecallResultList: View {
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow.opacity(0.7))

                Text("회상 결과")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))

                Text("\(noteStore.filteredSearchResults.count)건")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.yellow.opacity(0.5))

                Spacer()

                Button(action: { noteStore.clearSearch() }) {
                    Text("닫기")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.yellow.opacity(0.05))

            // Results
            LazyVStack(spacing: 2) {
                ForEach(noteStore.filteredSearchResults) { result in
                    let isSelected = noteStore.selectedFilePath == result.path
                    HStack(spacing: 12) {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        .yellow.opacity(result.score),
                                        .yellow.opacity(0.1),
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 6
                                )
                            )
                            .frame(width: 10, height: 10)
                            .shadow(color: .yellow.opacity(result.score * 0.6), radius: 4)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(resultFileName(result))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.9))
                                .lineLimit(1)

                            Text(result.chunkText)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.35))
                                .lineLimit(2)
                        }

                        Spacer()

                        Text("\(Int(result.score * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.yellow.opacity(0.7))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.yellow.opacity(0.1) : Color.white.opacity(0.03))
                            .padding(.horizontal, 4)
                    )
                    .onTapGesture {
                        noteStore.selectFile(path: result.path)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func resultFileName(_ result: SearchResult) -> String {
        let name = (result.filename as NSString).deletingPathExtension
        let ext = (result.filename as NSString).pathExtension.uppercased()
        return "\(name)  \(ext)"
    }
}
