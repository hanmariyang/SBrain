import SwiftUI
import WebKit

// MARK: - iOS Note Detail View (Read-Only Markdown)

struct IOSNoteDetailView: View {
    @EnvironmentObject var noteStore: NoteStore
    let path: String

    @State private var content: String?

    var body: some View {
        VStack(spacing: 0) {
            if let content = content {
                if FolderScanner.fileType(for: path) == .html {
                    IOSHTMLWebView(html: content, basePath: path)
                } else {
                    IOSMarkdownWebView(markdown: content)
                }
            } else {
                VStack(spacing: SB.Space.md) {
                    ProgressView()
                        .tint(SB.Colors.gold600)
                    Text("Loading...")
                        .font(SB.Font.bodySm())
                        .foregroundStyle(SB.Colors.navy300)
                }
            }
        }
        .background(SB.Colors.bgPrimary)
        .navigationTitle((path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            content = FolderScanner.readContent(at: path)
        }
    }
}

// MARK: - iOS Markdown WebView (UIViewRepresentable)

struct IOSMarkdownWebView: UIViewRepresentable {
    let markdown: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.navigationDelegate = context.coordinator
        return wv
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = wrapMarkdownHTML(markdown)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }

    private func wrapMarkdownHTML(_ markdown: String) -> String {
        let escaped = markdown
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
        <style>
            * { box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 15px;
                line-height: 1.6;
                color: #1B2A4A;
                background: #FAF8F5;
                padding: 16px;
                margin: 0;
                word-wrap: break-word;
                overflow-wrap: break-word;
            }
            h1 { font-size: 24px; font-weight: 700; color: #1B2A4A; border-bottom: 2px solid #D4DCE8; padding-bottom: 8px; }
            h2 { font-size: 20px; font-weight: 600; color: #2D4470; margin-top: 24px; }
            h3 { font-size: 17px; font-weight: 600; color: #2D4470; }
            p { margin: 8px 0; }
            a { color: #3B7CC4; text-decoration: none; }
            code {
                font-family: 'SF Mono', Menlo, monospace;
                font-size: 13px;
                background: #F2EDE8;
                padding: 2px 6px;
                border-radius: 4px;
                color: #C4973B;
            }
            pre {
                background: #F2EDE8;
                padding: 12px;
                border-radius: 8px;
                overflow-x: auto;
                border-left: 3px solid #C4973B;
            }
            pre code { background: none; padding: 0; color: #1B2A4A; }
            blockquote {
                border-left: 3px solid #C4973B;
                margin: 12px 0;
                padding: 8px 16px;
                background: #F5EDD8;
                border-radius: 0 6px 6px 0;
                color: #2D4470;
            }
            ul, ol { padding-left: 24px; }
            li { margin: 4px 0; }
            table { border-collapse: collapse; width: 100%; margin: 12px 0; }
            th, td { border: 1px solid #D4DCE8; padding: 8px; text-align: left; font-size: 13px; }
            th { background: #F2EDE8; font-weight: 600; }
            img { max-width: 100%; border-radius: 8px; }
            hr { border: none; border-top: 1px solid #D4DCE8; margin: 16px 0; }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script>
            document.getElementById('content').innerHTML = marked.parse(`\(escaped)`);
        </script>
        </body>
        </html>
        """
    }
}

// MARK: - iOS HTML WebView

struct IOSHTMLWebView: UIViewRepresentable {
    let html: String
    let basePath: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.navigationDelegate = context.coordinator
        return wv
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let baseDir = (basePath as NSString).deletingLastPathComponent
        let baseURL = URL(fileURLWithPath: baseDir)
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               url.scheme == "http" || url.scheme == "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
