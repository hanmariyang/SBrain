import SwiftUI
import SwiftTerm

// MARK: - Terminal Container (tabs + terminal content)

struct TerminalContainerView: View {
    @EnvironmentObject var terminalManager: TerminalManager
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        VStack(spacing: 0) {
            // Terminal tab bar
            TerminalTabBar()

            // Terminal content
            if let session = terminalManager.activeSession {
                SwiftTermView(terminalView: session.terminalView)
                    .id(session.id)
            } else {
                terminalEmptyState
            }
        }
        .background(Color(nsColor: NSColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1)))
        .onAppear {
            if terminalManager.sessions.isEmpty {
                let dir = noteStore.selectedProject?.path ?? NSHomeDirectory()
                terminalManager.createSession(workingDirectory: dir)
            }
        }
    }

    private var terminalEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.12))

            Text("터미널을 시작하려면 + 버튼을 클릭하세요")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.25))

            Button(action: {
                let dir = noteStore.selectedProject?.path ?? NSHomeDirectory()
                terminalManager.createSession(workingDirectory: dir)
            }) {
                Label("새 터미널", systemImage: "plus")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.2))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
        }
    }
}

// MARK: - Terminal Tab Bar

struct TerminalTabBar: View {
    @EnvironmentObject var terminalManager: TerminalManager
    @EnvironmentObject var noteStore: NoteStore

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(terminalManager.sessions) { session in
                        TerminalTab(
                            session: session,
                            isActive: terminalManager.activeSessionId == session.id,
                            onSelect: { terminalManager.switchTo(id: session.id) },
                            onClose: { terminalManager.removeSession(id: session.id) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            // New terminal button
            Button(action: {
                let dir = noteStore.selectedProject?.path ?? NSHomeDirectory()
                terminalManager.createSession(workingDirectory: dir)
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("새 터미널")
            .padding(.trailing, 8)
        }
        .frame(height: 32)
        .background(Color.black.opacity(0.4))
    }
}

struct TerminalTab: View {
    let session: TerminalSession
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange.opacity(isActive ? 0.9 : 0.5))

                Text(session.title)
                    .font(.system(size: 11, weight: isActive ? .bold : .medium))
                    .foregroundStyle(.white.opacity(isActive ? 0.9 : 0.5))
                    .lineLimit(1)

                if isHovered || isActive {
                    Button(action: onClose) {
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
                    .fill(isActive ? Color.orange.opacity(0.15) : .white.opacity(isHovered ? 0.06 : 0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isActive ? Color.orange.opacity(0.4) : .clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - SwiftTerm NSView Wrapper

struct SwiftTermView: NSViewRepresentable {
    let terminalView: LocalProcessTerminalView

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Terminal view manages its own state
    }
}
