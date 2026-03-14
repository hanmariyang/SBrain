import SwiftUI

@main
struct SBrainApp: App {
    @StateObject private var backendManager = BackendManager()
    @StateObject private var noteStore = NoteStore()
    @StateObject private var handTracking = HandTrackingManager()
    @StateObject private var dbStore = DatabaseStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(backendManager)
                .environmentObject(noteStore)
                .environmentObject(handTracking)
                .environmentObject(dbStore)
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
