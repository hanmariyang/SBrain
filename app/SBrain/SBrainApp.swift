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
                Button("프로젝트 추가...") {
                    noteStore.addFolder()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
