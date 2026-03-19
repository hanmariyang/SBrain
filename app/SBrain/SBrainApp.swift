import SwiftUI
import Sparkle

@main
struct SBrainApp: App {
    @StateObject private var backendManager = BackendManager()
    @StateObject private var noteStore = NoteStore()
    @StateObject private var handTracking = HandTrackingManager()
    @StateObject private var dbStore = DatabaseStore()
    @StateObject private var terminalManager = TerminalManager()

    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(backendManager)
                .environmentObject(noteStore)
                .environmentObject(handTracking)
                .environmentObject(dbStore)
                .environmentObject(terminalManager)
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
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
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
