import SwiftUI
import SwiftTerm

struct TerminalSession: Identifiable {
    let id = UUID()
    let title: String
    let localProcess: LocalProcess
    let terminalView: LocalProcessTerminalView
}

@MainActor
class TerminalManager: ObservableObject {
    @Published var sessions: [TerminalSession] = []
    @Published var activeSessionId: UUID?

    private var sessionCounter = 0

    var activeSession: TerminalSession? {
        guard let id = activeSessionId else { return sessions.first }
        return sessions.first { $0.id == id }
    }

    func createSession(workingDirectory: String? = nil) {
        sessionCounter += 1
        let title = "Terminal \(sessionCounter)"

        let terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))

        // Configure appearance
        terminalView.nativeForegroundColor = SBNSColor.navy900
        terminalView.nativeBackgroundColor = SBNSColor.bgPrimary
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.caretColor = SBNSColor.gold600
        terminalView.selectedTextBackgroundColor = SBNSColor.gold400.withAlphaComponent(0.2)
        terminalView.optionAsMetaKey = true

        // Determine shell and working directory
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let dir = workingDirectory ?? NSHomeDirectory()

        // Start the shell process
        terminalView.startProcess(executable: shell, args: [], environment: nil, execName: nil, currentDirectory: dir)

        guard let process = terminalView.process else {
            print("[TerminalManager] Failed to start shell process: \(shell)")
            return
        }

        let session = TerminalSession(
            title: title,
            localProcess: process,
            terminalView: terminalView
        )

        sessions.append(session)
        activeSessionId = session.id
    }

    func removeSession(id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[idx]

        // Kill the process
        session.localProcess.terminate()
        sessions.remove(at: idx)

        // Switch active to last remaining or nil
        if activeSessionId == id {
            activeSessionId = sessions.last?.id
        }
    }

    func switchTo(id: UUID) {
        activeSessionId = id
    }

    func removeAll() {
        for session in sessions {
            session.localProcess.terminate()
        }
        sessions.removeAll()
        activeSessionId = nil
        sessionCounter = 0
    }
}
