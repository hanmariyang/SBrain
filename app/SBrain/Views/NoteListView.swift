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
                .foregroundStyle(SB.Colors.navy900)

            if let root = project.rootFolder {
                Text("\(root.docFileCount)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(SB.Colors.navy300)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(SB.Colors.bgTertiary.opacity(0.5))
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
                            .foregroundStyle(SB.Colors.navy300)
                            .frame(width: 12)

                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 12))
                            .foregroundStyle(SB.Colors.gold600.opacity(0.7))

                        Text(node.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SB.Colors.navy700)

                        Text("\(node.docFileCount)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(SB.Colors.navy300)

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
                // File type icon
                Image(systemName: fileIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(fileIconColor)
                    .frame(width: 16)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text((node.name as NSString).deletingPathExtension)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isSelected ? SB.Colors.navy900 : SB.Colors.navy700)
                            .lineLimit(1)

                        Text(fileExtension.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(fileIconColor.opacity(0.7))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(fileIconColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }

                    if !node.preview.isEmpty {
                        Text(node.preview)
                            .font(.system(size: 10))
                            .foregroundStyle(SB.Colors.navy300)
                            .lineLimit(2)
                            .lineSpacing(1)
                    }
                }

                Spacer()

                if let date = node.modifiedAt {
                    Text(formatDate(date))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(SB.Colors.navy300)
                        .padding(.top, 2)
                }
            }
            .padding(.leading, CGFloat(depth) * 16 + 20)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? SB.Colors.gold100 : Color.clear)
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var fileExtension: String {
        (node.name as NSString).pathExtension.lowercased()
    }

    private var fileIcon: String {
        switch fileExtension {
        case "html", "htm":
            return "globe"
        case "md", "markdown":
            return "doc.text"
        case "txt":
            return "doc.plaintext"
        case "json":
            return "curlybraces"
        case "yaml", "yml":
            return "list.bullet.indent"
        case "csv":
            return "tablecells"
        case "pdf":
            return "doc.richtext"
        default:
            return "doc"
        }
    }

    private var fileIconColor: Color {
        switch fileExtension {
        case "html", "htm":
            return SB.Colors.accentOrange
        case "md", "markdown":
            return SB.Colors.accentBlue
        case "txt":
            return SB.Colors.navy500
        case "json":
            return SB.Colors.gold600
        case "yaml", "yml":
            return SB.Colors.accentGreen
        case "csv":
            return SB.Colors.accentGreen
        case "pdf":
            return SB.Colors.accentRed
        default:
            return SB.Colors.navy500
        }
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
                    .foregroundStyle(SB.Colors.gold600)

                Text("회상 결과")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SB.Colors.navy700)

                Text("\(noteStore.filteredSearchResults.count)건")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(SB.Colors.gold600)

                Spacer()

                Button(action: { noteStore.clearSearch() }) {
                    Text("닫기")
                        .font(.system(size: 10))
                        .foregroundStyle(SB.Colors.navy300)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(SB.Colors.gold100.opacity(0.5))

            // Results
            LazyVStack(spacing: 2) {
                ForEach(noteStore.filteredSearchResults) { result in
                    let isSelected = noteStore.selectedFilePath == result.path
                    HStack(spacing: 12) {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        SB.Colors.gold600.opacity(result.score),
                                        SB.Colors.gold400.opacity(0.1),
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 6
                                )
                            )
                            .frame(width: 10, height: 10)
                            .shadow(color: SB.Colors.gold600.opacity(result.score * 0.6), radius: 4)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(resultFileName(result))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(isSelected ? SB.Colors.navy900 : SB.Colors.navy700)
                                .lineLimit(1)

                            Text(result.chunkText)
                                .font(.system(size: 10))
                                .foregroundStyle(SB.Colors.navy300)
                                .lineLimit(2)
                        }

                        Spacer()

                        Text("\(Int(result.score * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(SB.Colors.gold600)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? SB.Colors.gold100 : SB.Colors.bgTertiary.opacity(0.3))
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
