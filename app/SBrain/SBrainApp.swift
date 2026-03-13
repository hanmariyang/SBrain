import SwiftUI

@main
struct SBrainApp: App {
    @StateObject private var backendManager = BackendManager()
    @StateObject private var noteStore = NoteStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(backendManager)
                .environmentObject(noteStore)
                .onAppear {
                    backendManager.start()
                }
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("폴더 열기...") {
                    noteStore.selectFolder()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("폴더 새로고침") {
                    noteStore.scanFolder()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
