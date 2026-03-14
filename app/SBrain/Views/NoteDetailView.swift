import SwiftUI
import WebKit

struct MemoryDetailView: View {
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(red: 0.06, green: 0.06, blue: 0.1, alpha: 1))

            if let content = noteStore.selectedFileContent,
               let fileName = noteStore.selectedFileName {
                VStack(spacing: 0) {
                    detailHeader(fileName: fileName)

                    // Gradient divider
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.cyan.opacity(0.4), .purple.opacity(0.4), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)

                    MarkdownWebView(markdown: content)
                }
            } else {
                emptyState
            }
        }
    }

    private func detailHeader(fileName: String) -> some View {
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
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var emptyState: some View {
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

// MARK: - Markdown WebView (WKWebView-based renderer)

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let escaped = escapeForJS(markdown)
        let html = Self.buildHTML(markdownContent: escaped)
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

    private static func buildHTML(markdownContent: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(Self.cssStyles)
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
        // Syntax highlighting for code blocks
        document.querySelectorAll('pre code').forEach(el => {
            el.classList.add('hljs');
        });
        </script>
        </body>
        </html>
        """
    }

    // Obsidian-inspired dark theme CSS
    private static let cssStyles = """
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
        font-size: 14px;
        line-height: 1.7;
        color: rgba(255,255,255,0.82);
        background: transparent;
        padding: 24px;
        -webkit-font-smoothing: antialiased;
    }
    ::selection { background: rgba(100,200,255,0.25); }

    /* Headings */
    h1, h2, h3, h4, h5, h6 {
        color: rgba(255,255,255,0.95);
        font-weight: 600;
        margin-top: 1.4em;
        margin-bottom: 0.5em;
        line-height: 1.3;
    }
    h1 { font-size: 1.8em; border-bottom: 1px solid rgba(255,255,255,0.08); padding-bottom: 0.3em; }
    h2 { font-size: 1.4em; border-bottom: 1px solid rgba(255,255,255,0.06); padding-bottom: 0.2em; }
    h3 { font-size: 1.15em; }
    h4 { font-size: 1.05em; color: rgba(255,255,255,0.85); }
    h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }

    /* Paragraphs */
    p { margin-bottom: 0.8em; }

    /* Links */
    a {
        color: #7eb8da;
        text-decoration: none;
        border-bottom: 1px solid rgba(126,184,218,0.3);
        transition: border-color 0.2s;
    }
    a:hover { border-bottom-color: #7eb8da; }

    /* Strong & Emphasis */
    strong { color: rgba(255,255,255,0.95); font-weight: 600; }
    em { color: rgba(255,255,255,0.75); font-style: italic; }

    /* Inline code */
    code {
        font-family: 'SF Mono', 'Fira Code', 'JetBrains Mono', Menlo, monospace;
        font-size: 0.88em;
        background: rgba(255,255,255,0.07);
        border: 1px solid rgba(255,255,255,0.06);
        border-radius: 4px;
        padding: 1px 5px;
        color: #d4a0e0;
    }

    /* Code blocks */
    pre {
        background: rgba(0,0,0,0.35);
        border: 1px solid rgba(255,255,255,0.06);
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
        color: rgba(255,255,255,0.75);
        line-height: 1.6;
    }

    /* Blockquote */
    blockquote {
        border-left: 3px solid rgba(126,184,218,0.4);
        padding: 0.5em 1em;
        margin: 1em 0;
        color: rgba(255,255,255,0.6);
        background: rgba(126,184,218,0.04);
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
        accent-color: #7eb8da;
    }

    /* Table */
    table {
        border-collapse: collapse;
        width: 100%;
        margin: 1em 0;
        font-size: 0.92em;
    }
    th, td {
        border: 1px solid rgba(255,255,255,0.08);
        padding: 8px 12px;
        text-align: left;
    }
    th {
        background: rgba(255,255,255,0.05);
        color: rgba(255,255,255,0.9);
        font-weight: 600;
    }
    tr:nth-child(even) { background: rgba(255,255,255,0.02); }

    /* Horizontal rule */
    hr {
        border: none;
        height: 1px;
        background: linear-gradient(to right, rgba(100,200,255,0.3), rgba(180,100,255,0.3), transparent);
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
        background: rgba(255,255,255,0.12);
        border-radius: 3px;
    }
    ::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.2); }

    /* Tags (Obsidian-like) */
    .tag {
        color: #7eb8da;
        background: rgba(126,184,218,0.1);
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
}
