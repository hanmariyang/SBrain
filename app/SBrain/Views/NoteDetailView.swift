import SwiftUI

struct MemoryDetailView: View {
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(red: 0.06, green: 0.06, blue: 0.1, alpha: 1))

            if let content = noteStore.selectedFileContent,
               let fileName = noteStore.selectedFileName {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fileName.replacingOccurrences(of: ".md", with: ""))
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(
                                        .linearGradient(
                                            colors: [.white, .white.opacity(0.7)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )

                                if let path = noteStore.selectedFilePath {
                                    Text(path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.2))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }

                            Spacer()

                            Button(action: {
                                noteStore.selectedFilePath = nil
                                noteStore.selectedFileContent = nil
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .frame(width: 24, height: 24)
                                    .background(.white.opacity(0.08))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }

                        // Divider
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.4), .purple.opacity(0.4), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 1)

                        // Markdown content
                        MarkdownView(markdown: content)
                    }
                    .padding(24)
                }
            } else {
                // No file selected
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.12))

                    Text("파일을 선택하면 여기에 미리보기가 표시됩니다")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
        }
    }
}

struct MarkdownView: View {
    let markdown: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .textSelection(.enabled)
                .font(.system(size: 13, design: .default))
                .foregroundStyle(.white.opacity(0.8))
                .lineSpacing(4)
        } else {
            Text(markdown)
                .textSelection(.enabled)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .lineSpacing(4)
        }
    }
}
