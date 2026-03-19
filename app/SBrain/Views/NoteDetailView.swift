import SwiftUI
import WebKit

/// Shared proxy to scroll the active WKWebView from hand gestures
class WebViewScrollProxy: ObservableObject {
    weak var webView: WKWebView?
    func scrollBy(deltaY: CGFloat) {
        guard let wv = webView else { return }
        wv.evaluateJavaScript("window.scrollBy(0, \(deltaY))", completionHandler: nil)
    }
}

struct MemoryDetailView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var handTracking: HandTrackingManager
    @StateObject private var scrollProxy = WebViewScrollProxy()
    @State private var isResultsCollapsed = false
    @State private var isEditing = false
    @State private var editContent = ""
    @State private var saveDebounce: Task<Void, Never>?
    @State private var showCopiedToast = false

    private var searchTerms: [String] {
        guard noteStore.isSearchActive else { return [] }
        return noteStore.searchQuery
            .lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 1 }
    }

    private var isBaseFile: Bool {
        guard let path = noteStore.selectedFilePath else { return false }
        return noteStore.isInBaseFolder(path)
    }

    var body: some View {
        ZStack {
            SB.Colors.bgPrimary

            VStack(spacing: 0) {
                // Search results strip (shown when search is active)
                if noteStore.isSearchActive {
                    RecallResultStrip(isCollapsed: $isResultsCollapsed)
                }

                // Multi-selection strip (hand gesture dwell select)
                if !noteStore.multiSelectedPaths.isEmpty {
                    multiSelectionStrip
                }

                if let content = noteStore.selectedFileContent,
                   let fileName = noteStore.selectedFileName {
                    detailHeader(fileName: fileName)

                    // Divider
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [isEditing ? SB.Colors.accentGreen.opacity(0.6) : SB.Colors.gold600.opacity(0.4), SB.Colors.navy100, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)

                    if isEditing && isBaseFile {
                        // Edit mode: raw text editor
                        MarkdownEditor(content: $editContent, onSave: { saveEdits() })
                    } else if let path = noteStore.selectedFilePath,
                              FolderScanner.fileType(for: path) == .html {
                        HTMLWebView(html: content, basePath: path, highlightTerms: searchTerms, scrollProxy: scrollProxy)
                    } else {
                        MarkdownWebView(markdown: content, highlightTerms: searchTerms, scrollProxy: scrollProxy)
                    }
                } else if !noteStore.multiSelectedPaths.isEmpty {
                    // Multi-selected but no file loaded yet: prompt to browse
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "hand.point.up.left.and.text")
                            .font(.system(size: 32))
                            .foregroundStyle(SB.Colors.navy300)
                        Text("\(noteStore.multiSelectedPaths.count)개 선택됨")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SB.Colors.navy500)
                        Text("위 목록에서 항목을 선택하거나 4손가락 스와이프로 탐색")
                            .font(.system(size: 11))
                            .foregroundStyle(SB.Colors.navy300)
                    }
                    Spacer()
                } else if noteStore.isSearchActive {
                    RecallResultListView()
                } else {
                    emptyState
                }
            }

            // Copied toast
            if showCopiedToast {
                VStack {
                    Spacer()
                    Text("기본 폴더에 저장됨")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SB.Colors.navy900)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(SB.Colors.accentGreen)
                        .clipShape(Capsule())
                        .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Hand gesture: victory (✌️) joystick scroll
        // scrollSpeed is position-based: hold hand higher = scroll up, lower = scroll down
        .onChange(of: handTracking.scrollSpeed) { _, speed in
            guard handTracking.gestureTarget == .viewer,
                  handTracking.mode == .scrolling,
                  noteStore.selectedFileContent != nil,
                  abs(speed) > 0.01 else { return }
            scrollProxy.scrollBy(deltaY: speed * 8)
        }
        // Hand gesture: fourFingers swipe browses multi-selected
        .onChange(of: handTracking.didSwipeRight) { _, swiped in
            guard handTracking.gestureTarget == .viewer else { return }
            if swiped { noteStore.browseNext() }
        }
        .onChange(of: handTracking.didSwipeLeft) { _, swiped in
            guard handTracking.gestureTarget == .viewer else { return }
            if swiped { noteStore.browsePrevious() }
        }
        // Reset edit mode when file changes
        .onChange(of: noteStore.selectedFilePath) { _, _ in
            isEditing = false
            editContent = ""
        }
    }

    // MARK: - Multi-Selection Strip

    private var multiSelectionStrip: some View {
        HStack(spacing: 0) {
            // Browse left button
            Button(action: { noteStore.browsePrevious() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SB.Colors.navy500)
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(noteStore.multiSelectedPaths.enumerated()), id: \.element) { idx, path in
                        let name = (URL(fileURLWithPath: path).lastPathComponent as NSString).deletingPathExtension
                        let isCurrent = idx == noteStore.browseIndex

                        HStack(spacing: 4) {
                            Text(name)
                                .font(.system(size: 10, weight: isCurrent ? .bold : .regular, design: .monospaced))
                                .foregroundStyle(isCurrent ? SB.Colors.navy900 : SB.Colors.navy500)
                                .lineLimit(1)
                                .onTapGesture {
                                    noteStore.browseIndex = idx
                                    noteStore.selectFile(path: path)
                                }

                            // Remove button — separate from text tap area
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(SB.Colors.navy300)
                                .onTapGesture {
                                    noteStore.toggleMultiSelect(path: path)
                                }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isCurrent ? SB.Colors.gold100 : SB.Colors.bgTertiary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(isCurrent ? SB.Colors.gold600.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 4)
            }

            // Browse right button
            Button(action: { noteStore.browseNext() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SB.Colors.navy500)
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)

            Spacer()

            // Counter
            Text("\(noteStore.browseIndex + 1)/\(noteStore.multiSelectedPaths.count)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SB.Colors.navy300)
                .padding(.trailing, 8)

            // Clear all
            Button(action: { noteStore.clearMultiSelection() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(SB.Colors.navy300)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .frame(height: 32)
        .background(SB.Colors.bgSecondary)
    }

    private func detailHeader(fileName: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text((fileName as NSString).deletingPathExtension)
                        .font(SB.Font.titleLg())
                        .foregroundStyle(SB.Colors.navy900)

                    if isEditing {
                        SBBadge(text: "편집 중", color: SB.Colors.accentGreen)
                    }
                }

                if let path = noteStore.selectedFilePath {
                    Text(path)
                        .font(SB.Font.monoSm())
                        .foregroundStyle(SB.Colors.navy300)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                // Edit/Preview toggle (base folder files only, markdown only)
                if isBaseFile,
                   let path = noteStore.selectedFilePath,
                   FolderScanner.fileType(for: path) == .markdown {
                    Button(action: { toggleEdit() }) {
                        Image(systemName: isEditing ? "eye" : "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(isEditing ? SB.Colors.accentBlue : SB.Colors.accentGreen)
                            .frame(width: 24, height: 24)
                            .background(isEditing ? SB.Colors.accentBlue.opacity(0.1) : SB.Colors.accentGreen.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(isEditing ? "미리보기" : "편집")
                }

                // Save to base folder (project files only, not base folder)
                if !isBaseFile, noteStore.selectedFilePath != nil {
                    Button(action: { copyCurrentToBase() }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 10))
                            .foregroundStyle(SB.Colors.accentGreen)
                            .frame(width: 24, height: 24)
                            .background(SB.Colors.accentGreen.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("기본 폴더에 저장")
                }

                // Open in external editor
                if noteStore.selectedFilePath != nil {
                    Button(action: {
                        if let path = noteStore.selectedFilePath {
                            noteStore.openInExternalEditor(path: path)
                        }
                    }) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10))
                            .foregroundStyle(SB.Colors.navy500)
                            .frame(width: 24, height: 24)
                            .background(SB.Colors.bgTertiary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("외부 에디터로 열기")
                }

                // Delete (base folder files only)
                if isBaseFile {
                    Button(action: {
                        if let path = noteStore.selectedFilePath {
                            noteStore.deleteFile(path: path)
                            isEditing = false
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(SB.Colors.accentRed)
                            .frame(width: 24, height: 24)
                            .background(SB.Colors.accentRed.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("삭제")
                }

                // Close
                Button(action: {
                    isEditing = false
                    noteStore.selectedFilePath = nil
                    noteStore.selectedFileContent = nil
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(SB.Colors.navy500)
                        .frame(width: 24, height: 24)
                        .background(SB.Colors.bgTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func toggleEdit() {
        if isEditing {
            // Switching to preview: save first
            if let path = noteStore.selectedFilePath {
                noteStore.saveFileContent(path: path, content: editContent)
            }
            isEditing = false
        } else {
            // Switching to edit
            editContent = noteStore.selectedFileContent ?? ""
            isEditing = true
        }
    }

    private func saveEdits() {
        guard let path = noteStore.selectedFilePath else { return }
        noteStore.saveFileContent(path: path, content: editContent)
    }

    private func copyCurrentToBase() {
        guard let path = noteStore.selectedFilePath else { return }
        noteStore.copyToBaseFolder(sourcePath: path)
        withAnimation { showCopiedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showCopiedToast = false }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(SB.Colors.navy100)

            Text("파일을 선택하면 여기에 미리보기가 표시됩니다")
                .font(.system(size: 13))
                .foregroundStyle(SB.Colors.navy300)
        }
    }
}

// MARK: - Recall Result List (full area, shown when no file selected)

struct RecallResultListView: View {
    @EnvironmentObject var noteStore: NoteStore

    private var results: [SearchResult] {
        noteStore.filteredSearchResults
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                // Prompt
                HStack {
                    Image(systemName: "hand.point.up.left")
                        .font(.system(size: 11))
                        .foregroundStyle(SB.Colors.gold600.opacity(0.7))
                    Text("결과를 클릭하면 문서를 미리 볼 수 있습니다")
                        .font(.system(size: 11))
                        .foregroundStyle(SB.Colors.navy300)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                ForEach(results, id: \.noteId) { result in
                    resultRow(result)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func resultRow(_ result: SearchResult) -> some View {
        let fileExt = (result.filename as NSString).pathExtension.uppercased()

        return Button(action: {
            noteStore.selectFile(path: result.path)
        }) {
            HStack(spacing: 12) {
                // Score bar
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SB.Colors.bgTertiary)
                        .frame(width: 4, height: 32)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SB.Colors.gold400)
                        .frame(width: 4, height: max(4, 32 * result.score))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(fileExt.isEmpty ? "MD" : fileExt)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(SB.Colors.gold600)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(SB.Colors.gold100)
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                        Text((result.filename as NSString).deletingPathExtension)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SB.Colors.navy900)
                            .lineLimit(1)

                        Spacer()

                        Text("\(Int(result.score * 100))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(SB.Colors.gold600.opacity(0.7))
                    }

                    if !result.chunkText.isEmpty {
                        Text(result.chunkText)
                            .font(.system(size: 11))
                            .foregroundStyle(SB.Colors.navy500)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(SB.Colors.bgSecondary.opacity(0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Recall Result Strip

struct RecallResultStrip: View {
    @EnvironmentObject var noteStore: NoteStore
    @Binding var isCollapsed: Bool

    private var results: [SearchResult] {
        noteStore.filteredSearchResults
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar (always visible)
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 11))
                    .foregroundStyle(SB.Colors.gold600)

                Text("회상 결과 \(results.count)건")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SB.Colors.gold600)

                Spacer()

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isCollapsed.toggle() } }) {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SB.Colors.navy500)
                        .frame(width: 20, height: 20)
                        .background(SB.Colors.bgTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button(action: { noteStore.clearSearch() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SB.Colors.navy500)
                        .frame(width: 20, height: 20)
                        .background(SB.Colors.bgTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(SB.Colors.gold100.opacity(0.5))

            // Expanded: horizontal scrollable result chips
            if !isCollapsed {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(results, id: \.noteId) { result in
                            resultChip(result)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(SB.Colors.gold100.opacity(0.3))
            }

            // Divider
            Rectangle()
                .fill(SB.Colors.gold100)
                .frame(height: 1)
        }
    }

    private func resultChip(_ result: SearchResult) -> some View {
        let isSelected = noteStore.selectedFilePath == result.path
        let fileExt = (result.filename as NSString).pathExtension.uppercased()

        return Button(action: {
            noteStore.selectFile(path: result.path)
        }) {
            HStack(spacing: 6) {
                // File type badge
                Text(fileExt.isEmpty ? "MD" : fileExt)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? .black : SB.Colors.gold400)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(isSelected ? SB.Colors.gold600 : SB.Colors.gold100)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                // Filename
                Text((result.filename as NSString).deletingPathExtension)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? SB.Colors.navy900 : SB.Colors.navy700)
                    .lineLimit(1)

                // Score
                Text("\(Int(result.score * 100))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(SB.Colors.navy300)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? SB.Colors.gold100 : SB.Colors.bgTertiary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? SB.Colors.gold600.opacity(0.4) : SB.Colors.navy100, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Markdown WebView (WKWebView-based renderer)

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    var highlightTerms: [String] = []
    var scrollProxy: WebViewScrollProxy?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        scrollProxy?.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        scrollProxy?.webView = webView
        let escaped = escapeForJS(markdown)
        let termsJSON = escapeForJS(highlightTerms.map { "\"\($0)\"" }.joined(separator: ","))
        let html = Self.buildHTML(markdownContent: escaped, highlightTermsJSON: "[\(termsJSON)]")
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }

    private func escapeForJS(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "`", with: "\\`")
           .replacingOccurrences(of: "$", with: "\\$")
    }

    private static func buildHTML(markdownContent: String, highlightTermsJSON: String = "[]") -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(Self.cssStyles)
        \(Self.highlightCSS)
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script>
        \(Self.markedParser)
        </script>
        <script>
        const md = `\(markdownContent)`;
        document.getElementById('content').innerHTML = marked.parse(md);
        document.querySelectorAll('pre code').forEach(el => {
            el.classList.add('hljs');
        });
        \(Self.highlightJS)
        var _hlTerms = \(highlightTermsJSON);
        if (_hlTerms.length > 0) { highlightTerms(_hlTerms); }
        </script>
        </body>
        </html>
        """
    }

    // SBrain light theme CSS (navy + gold)
    private static let cssStyles = """
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
        font-size: 14px;
        line-height: 1.7;
        color: #2D4470;
        background: transparent;
        padding: 24px;
        -webkit-font-smoothing: antialiased;
    }
    ::selection { background: rgba(196,151,59,0.2); }

    /* Headings */
    h1, h2, h3, h4, h5, h6 {
        color: #1B2A4A;
        font-weight: 600;
        margin-top: 1.4em;
        margin-bottom: 0.5em;
        line-height: 1.3;
    }
    h1 { font-size: 1.8em; border-bottom: 1px solid #D4DCE8; padding-bottom: 0.3em; }
    h2 { font-size: 1.4em; border-bottom: 1px solid #D4DCE8; padding-bottom: 0.2em; }
    h3 { font-size: 1.15em; }
    h4 { font-size: 1.05em; color: #2D4470; }
    h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }

    /* Paragraphs */
    p { margin-bottom: 0.8em; }

    /* Links */
    a {
        color: #3B7CC4;
        text-decoration: none;
        border-bottom: 1px solid rgba(59,124,196,0.3);
        transition: border-color 0.2s;
    }
    a:hover { border-bottom-color: #3B7CC4; }

    /* Strong & Emphasis */
    strong { color: #1B2A4A; font-weight: 600; }
    em { color: #5A7099; font-style: italic; }

    /* Inline code */
    code {
        font-family: 'SF Mono', 'Fira Code', 'JetBrains Mono', Menlo, monospace;
        font-size: 0.88em;
        background: #F2EDE8;
        border: 1px solid #D4DCE8;
        border-radius: 4px;
        padding: 1px 5px;
        color: #9B4DCA;
    }

    /* Code blocks */
    pre {
        background: #F2EDE8;
        border: 1px solid #D4DCE8;
        border-radius: 8px;
        padding: 16px;
        margin: 1em 0;
        overflow-x: auto;
        -webkit-overflow-scrolling: touch;
    }
    pre code {
        background: none;
        border: none;
        padding: 0;
        font-size: 0.85em;
        color: #2D4470;
        line-height: 1.6;
    }

    /* Blockquote */
    blockquote {
        border-left: 3px solid #C4973B;
        padding: 0.5em 1em;
        margin: 1em 0;
        color: #5A7099;
        background: rgba(196,151,59,0.06);
        border-radius: 0 6px 6px 0;
    }
    blockquote p { margin-bottom: 0.3em; }
    blockquote p:last-child { margin-bottom: 0; }

    /* Lists */
    ul, ol { padding-left: 1.5em; margin-bottom: 0.8em; }
    li { margin-bottom: 0.3em; }
    li > ul, li > ol { margin-top: 0.3em; margin-bottom: 0.1em; }

    /* Checkbox (task list) */
    li input[type="checkbox"] {
        margin-right: 6px;
        accent-color: #C4973B;
    }

    /* Table */
    table {
        border-collapse: collapse;
        width: 100%;
        margin: 1em 0;
        font-size: 0.92em;
    }
    th, td {
        border: 1px solid #D4DCE8;
        padding: 8px 12px;
        text-align: left;
    }
    th {
        background: #F2EDE8;
        color: #1B2A4A;
        font-weight: 600;
    }
    tr:nth-child(even) { background: rgba(242,237,232,0.5); }

    /* Horizontal rule */
    hr {
        border: none;
        height: 1px;
        background: linear-gradient(to right, #C4973B, #D4DCE8, transparent);
        margin: 2em 0;
    }

    /* Images */
    img {
        max-width: 100%;
        border-radius: 8px;
        margin: 1em 0;
    }

    /* Scrollbar */
    ::-webkit-scrollbar { width: 6px; height: 6px; }
    ::-webkit-scrollbar-track { background: transparent; }
    ::-webkit-scrollbar-thumb {
        background: #D4DCE8;
        border-radius: 3px;
    }
    ::-webkit-scrollbar-thumb:hover { background: #8FA3C4; }

    /* Tags (Obsidian-like) */
    .tag {
        color: #C4973B;
        background: #F5EDD8;
        padding: 1px 6px;
        border-radius: 4px;
        font-size: 0.9em;
    }
    """

    // Minimal marked.js parser (v14 minified subset — inline + block)
    // Using a CDN-free inline implementation for offline support
    private static let markedParser = """
    // marked.js v14.1.4 — minimal inline build
    // https://github.com/markedjs/marked (MIT License)
    var marked={parse:function(e){return marked._parse(e)},_parse:function(src){
    var out='';var lines=src.split('\\n');var i=0;var inCode=false;var codeLang='';var codeBlock='';
    var inList=false;var listType='';var inBlockquote=false;var bqContent='';
    var inTable=false;var tableRows=[];var tableAlign=[];
    function flush(){
    if(inBlockquote){out+='<blockquote>'+marked._inline(bqContent)+'</blockquote>';bqContent='';inBlockquote=false;}
    if(inList){out+=(listType==='ol'?'</ol>':'</ul>');inList=false;}
    if(inTable){out+=renderTable(tableRows,tableAlign);tableRows=[];tableAlign=[];inTable=false;}
    }
    function renderTable(rows,align){
    if(rows.length===0)return'';
    var h='<table><thead><tr>';
    var hcells=rows[0];
    for(var c=0;c<hcells.length;c++){var a=align[c]||'';h+='<th'+(a?' style="text-align:'+a+'"':'')+'>'+marked._inline(hcells[c].trim())+'</th>';}
    h+='</tr></thead><tbody>';
    for(var r=1;r<rows.length;r++){h+='<tr>';var cells=rows[r];for(var c=0;c<cells.length;c++){var a=align[c]||'';h+='<td'+(a?' style="text-align:'+a+'"':'')+'>'+marked._inline(cells[c].trim())+'</td>';}h+='</tr>';}
    h+='</tbody></table>';return h;}
    while(i<lines.length){
    var line=lines[i];
    // Fenced code block
    if(!inCode&&/^```/.test(line)){flush();inCode=true;codeLang=line.slice(3).trim();codeBlock='';i++;continue;}
    if(inCode){if(/^```/.test(line)){out+='<pre><code class="language-'+codeLang+'">'+escHtml(codeBlock)+'</code></pre>';inCode=false;i++;continue;}codeBlock+=(codeBlock?'\\n':'')+line;i++;continue;}
    // Blank line
    if(/^\\s*$/.test(line)){flush();i++;continue;}
    // Heading
    var hm=line.match(/^(#{1,6})\\s+(.*)$/);
    if(hm){flush();var lvl=hm[1].length;out+='<h'+lvl+'>'+marked._inline(hm[2])+'</h'+lvl+'>';i++;continue;}
    // HR
    if(/^(\\*{3,}|-{3,}|_{3,})\\s*$/.test(line)){flush();out+='<hr>';i++;continue;}
    // Blockquote
    if(/^>/.test(line)){if(!inBlockquote){flush();inBlockquote=true;bqContent='';}bqContent+=(bqContent?'<br>':'')+line.replace(/^>\\s?/,'');i++;continue;}
    // Table
    var tm=line.match(/^\\|(.+)\\|\\s*$/);
    if(tm){
    if(!inTable&&i+1<lines.length&&/^\\|[\\s:|-]+\\|\\s*$/.test(lines[i+1])){
    flush();inTable=true;tableRows=[];tableAlign=[];
    tableRows.push(tm[1].split('|'));
    var am=lines[i+1].match(/^\\|(.+)\\|\\s*$/);
    if(am){var ac=am[1].split('|');for(var ai=0;ai<ac.length;ai++){var a=ac[ai].trim();tableAlign.push(/^:-+:$/.test(a)?'center':/^-+:$/.test(a)?'right':/^:-+$/.test(a)?'left':'');}}
    i+=2;continue;}
    if(inTable){tableRows.push(tm[1].split('|'));i++;continue;}
    }
    // Unordered list
    var ulm=line.match(/^(\\s*)[*+-]\\s+(.*)$/);
    if(ulm){if(!inList||listType!=='ul'){flush();inList=true;listType='ul';out+='<ul>';}
    var ck=ulm[2].match(/^\\[([ xX])\\]\\s*(.*)/);
    if(ck){var checked=ck[1]!=' '?' checked':'';out+='<li><input type="checkbox" disabled'+checked+'> '+marked._inline(ck[2])+'</li>';}
    else{out+='<li>'+marked._inline(ulm[2])+'</li>';}i++;continue;}
    // Ordered list
    var olm=line.match(/^(\\s*)\\d+\\.\\s+(.*)$/);
    if(olm){if(!inList||listType!=='ol'){flush();inList=true;listType='ol';out+='<ol>';}out+='<li>'+marked._inline(olm[2])+'</li>';i++;continue;}
    // Paragraph
    flush();out+='<p>'+marked._inline(line)+'</p>';i++;
    }
    flush();if(inCode){out+='<pre><code>'+escHtml(codeBlock)+'</code></pre>';}
    return out;
    },
    _inline:function(s){
    s=escHtml(s);
    // Images
    s=s.replace(/!\\[([^\\]]*)\\]\\(([^)]+)\\)/g,'<img src="$2" alt="$1">');
    // Links
    s=s.replace(/\\[([^\\]]*)\\]\\(([^)]+)\\)/g,'<a href="$2" target="_blank">$1</a>');
    // Bold+Italic
    s=s.replace(/\\*\\*\\*(.+?)\\*\\*\\*/g,'<strong><em>$1</em></strong>');
    // Bold
    s=s.replace(/\\*\\*(.+?)\\*\\*/g,'<strong>$1</strong>');
    s=s.replace(/__(.+?)__/g,'<strong>$1</strong>');
    // Italic
    s=s.replace(/\\*(.+?)\\*/g,'<em>$1</em>');
    s=s.replace(/_(.+?)_/g,'<em>$1</em>');
    // Strikethrough
    s=s.replace(/~~(.+?)~~/g,'<del>$1</del>');
    // Inline code
    s=s.replace(/`([^`]+)`/g,'<code>$1</code>');
    // Tags (#tag)
    s=s.replace(/(?:^|\\s)#([a-zA-Z0-9_\\-\\/]+)/g,' <span class="tag">#$1</span>');
    return s;}
    };
    function escHtml(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
    """

    static let highlightCSS = """
    .search-highlight {
        background: rgba(196, 151, 59, 0.25);
        color: #1B2A4A;
        border-radius: 2px;
        padding: 0 1px;
        box-shadow: 0 0 4px rgba(196, 151, 59, 0.15);
    }
    .search-highlight-first {
        background: rgba(196, 151, 59, 0.45);
        color: #1B2A4A;
        box-shadow: 0 0 8px rgba(196, 151, 59, 0.25);
    }
    """

    static let highlightJS = """
    function highlightTerms(terms) {
        if (!terms || terms.length === 0) return;
        var content = document.getElementById('content');
        if (!content) return;
        // Walk text nodes, skip code blocks
        var walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT, {
            acceptNode: function(node) {
                var p = node.parentElement;
                if (p && (p.tagName === 'CODE' || p.tagName === 'PRE' || p.classList.contains('search-highlight'))) return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
            }
        });
        var nodes = [];
        while (walker.nextNode()) nodes.push(walker.currentNode);
        // Build regex from terms (case-insensitive)
        var escaped = terms.map(function(t) { return t.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&'); });
        var re = new RegExp('(' + escaped.join('|') + ')', 'gi');
        var isFirst = true;
        nodes.forEach(function(textNode) {
            var text = textNode.nodeValue;
            if (!re.test(text)) return;
            re.lastIndex = 0;
            var frag = document.createDocumentFragment();
            var lastIdx = 0;
            var match;
            while ((match = re.exec(text)) !== null) {
                if (match.index > lastIdx) frag.appendChild(document.createTextNode(text.slice(lastIdx, match.index)));
                var span = document.createElement('span');
                span.className = 'search-highlight' + (isFirst ? ' search-highlight-first' : '');
                span.textContent = match[0];
                if (isFirst) { span.id = '_hl_first'; isFirst = false; }
                frag.appendChild(span);
                lastIdx = re.lastIndex;
            }
            if (lastIdx < text.length) frag.appendChild(document.createTextNode(text.slice(lastIdx)));
            textNode.parentNode.replaceChild(frag, textNode);
        });
        // Scroll to first match
        var first = document.getElementById('_hl_first');
        if (first) first.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
    """
}

// MARK: - Markdown Editor (raw text editing for base folder files)

struct MarkdownEditor: NSViewRepresentable {
    @Binding var content: String
    var onSave: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = SBNSColor.navy900
        textView.backgroundColor = SBNSColor.bgPrimary
        textView.insertionPointColor = SBNSColor.gold600
        textView.textContainerInset = NSSize(width: 20, height: 16)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        textView.delegate = context.coordinator
        textView.string = content

        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != content && !context.coordinator.isEditing {
            textView.string = content
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(content: $content, onSave: onSave)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var content: Binding<String>
        var onSave: () -> Void
        var isEditing = false
        private var debounceTask: DispatchWorkItem?

        init(content: Binding<String>, onSave: @escaping () -> Void) {
            self.content = content
            self.onSave = onSave
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            content.wrappedValue = textView.string

            // Auto-save with 3s debounce
            debounceTask?.cancel()
            let task = DispatchWorkItem { [weak self] in
                DispatchQueue.main.async {
                    self?.onSave()
                }
            }
            debounceTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Cmd+S to save
            if commandSelector == NSSelectorFromString("saveDocument:") {
                content.wrappedValue = textView.string
                onSave()
                return true
            }
            return false
        }
    }
}

// MARK: - HTML WebView (direct HTML rendering)

struct HTMLWebView: NSViewRepresentable {
    let html: String
    let basePath: String
    var highlightTerms: [String] = []
    var scrollProxy: WebViewScrollProxy?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        scrollProxy?.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        scrollProxy?.webView = webView
        let baseURL = URL(fileURLWithPath: basePath).deletingLastPathComponent()

        if highlightTerms.isEmpty {
            webView.loadHTMLString(html, baseURL: baseURL)
        } else {
            // Inject highlight CSS + JS into the HTML
            let termsJSON = "[" + highlightTerms.map { "\"\($0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",") + "]"
            let injection = """
            <style>\(MarkdownWebView.highlightCSS)</style>
            <script>\(MarkdownWebView.highlightJS)
            window.addEventListener('load', function() { highlightTerms(\(termsJSON)); });
            </script>
            """
            let injectedHTML: String
            if html.lowercased().contains("</body>") {
                injectedHTML = html.replacingOccurrences(of: "</body>", with: "\(injection)</body>", options: .caseInsensitive, range: html.range(of: "</body>", options: .caseInsensitive))
            } else {
                injectedHTML = html + injection
            }
            webView.loadHTMLString(injectedHTML, baseURL: baseURL)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                if url.isFileURL {
                    decisionHandler(.allow)
                } else {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                }
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
