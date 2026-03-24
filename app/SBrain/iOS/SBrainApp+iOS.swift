import SwiftUI

@main
struct SBrainIOSApp: App {
    @StateObject private var noteStore = NoteStore()
    @StateObject private var syncManager = SyncManager()
    @StateObject private var slackStore = SlackStore()
    @StateObject private var calendarStore = CalendarStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(noteStore)
                .environmentObject(syncManager)
                .environmentObject(slackStore)
                .environmentObject(calendarStore)
                .onAppear {
                    noteStore.syncManager = syncManager
                }
        }
    }
}

// MARK: - Root View (Auth Gate)

struct RootView: View {
    @EnvironmentObject var syncManager: SyncManager

    var body: some View {
        if syncManager.isCloudAuthenticated {
            IOSContentView()
        } else {
            AuthView()
        }
    }
}
