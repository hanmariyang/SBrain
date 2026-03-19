import SwiftUI
import SwiftTerm

// MARK: - Terminal Container (tabs + terminal content)

struct TerminalContainerView: View {
    @EnvironmentObject var terminalManager: TerminalManager
    @EnvironmentObject var noteStore: NoteStore
    /// When true, auto-creates a session on appear if none exist
    var autoCreate: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Terminal tab bar
            TerminalTabBar()

            // Terminal content
            if let session = terminalManager.activeSession {
                SwiftTermView(terminalView: session.terminalView)
                    .id(session.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                terminalEmptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(SB.Colors.bgPrimary)
        .onAppear {
            if autoCreate && terminalManager.sessions.isEmpty {
                let dir = noteStore.selectedProject?.path ?? NSHomeDirectory()
                terminalManager.createSession(workingDirectory: dir)
            }
        }
    }

    private var terminalEmptyState: some View {
        VStack(spacing: SB.Space.md) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(SB.Colors.navy100)

            Text("터미널을 시작하려면 + 버튼을 클릭하세요")
                .font(SB.Font.bodyMd())
                .foregroundStyle(SB.Colors.navy300)

            Button(action: {
                let dir = noteStore.selectedProject?.path ?? NSHomeDirectory()
                terminalManager.createSession(workingDirectory: dir)
            }) {
                Label("새 터미널", systemImage: "plus")
            }
            .buttonStyle(SBGoldButtonStyle())
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
                    .foregroundStyle(SB.Colors.navy500)
                    .frame(width: 24, height: 24)
                    .background(SB.Colors.bgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("새 터미널")
            .padding(.trailing, 8)
        }
        .frame(height: 32)
        .background(SB.Colors.bgSecondary)
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
                    .foregroundStyle(isActive ? SB.Colors.gold600 : SB.Colors.navy500)

                Text(session.title)
                    .font(.system(size: 11, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? SB.Colors.navy900 : SB.Colors.navy500)
                    .lineLimit(1)

                if isHovered || isActive {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(SB.Colors.navy300)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: SB.Radius.sm)
                    .fill(isActive ? SB.Colors.gold100 : (isHovered ? SB.Colors.bgTertiary : Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: SB.Radius.sm)
                            .stroke(isActive ? SB.Colors.gold600.opacity(0.4) : .clear, lineWidth: 1)
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

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Detach from previous superview if reused (full ↔ panel switch)
        terminalView.removeFromSuperview()
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: container.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-attach if terminalView was stolen by another container
        if terminalView.superview !== nsView {
            terminalView.removeFromSuperview()
            terminalView.translatesAutoresizingMaskIntoConstraints = false
            nsView.addSubview(terminalView)
            NSLayoutConstraint.activate([
                terminalView.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                terminalView.trailingAnchor.constraint(equalTo: nsView.trailingAnchor),
                terminalView.topAnchor.constraint(equalTo: nsView.topAnchor),
                terminalView.bottomAnchor.constraint(equalTo: nsView.bottomAnchor),
            ])
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        // Remove terminal view from container without destroying it
        // (it may be reused when switching between full/panel modes)
        for subview in nsView.subviews {
            subview.removeFromSuperview()
        }
    }
}
