import SwiftUI
import Sparkle

@main
struct SBrainApp: App {
    @StateObject private var backendManager = BackendManager()
    @StateObject private var noteStore = NoteStore()
    @StateObject private var handTracking = HandTrackingManager()
    @StateObject private var dbStore = DatabaseStore()
    @StateObject private var terminalManager = TerminalManager()
    @StateObject private var slackStore = SlackStore()
    @StateObject private var calendarStore = CalendarStore()
    @StateObject private var fileMonitor = FileMonitor()
    @StateObject private var syncManager = SyncManager()

    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        Analytics.initialize()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(backendManager)
                .environmentObject(noteStore)
                .environmentObject(handTracking)
                .environmentObject(dbStore)
                .environmentObject(terminalManager)
                .environmentObject(slackStore)
                .environmentObject(calendarStore)
                .environmentObject(fileMonitor)
                .environmentObject(syncManager)
                .onAppear {
                    noteStore.syncManager = syncManager
                    backendManager.start()
                    Analytics.appLaunch()
                    // 앱 시작 2초 후 업데이트 자동 확인
                    checkForUpdatesOnLaunch()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("프로젝트 추가...") {
                    noteStore.addFolder()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
    /// 앱 시작 시 Sparkle 업데이트 자동 확인
    private func checkForUpdatesOnLaunch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let updater = updaterController.updater
            if updater.canCheckForUpdates {
                updater.checkForUpdatesInBackground()
            }
        }
    }
}

// MARK: - Check for Updates Menu Item

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("업데이트 확인...", action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private var cancellable: Any?

    init(updater: SPUUpdater) {
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)
    }
}
