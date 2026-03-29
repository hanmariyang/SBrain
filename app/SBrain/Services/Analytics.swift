import Foundation
import TelemetryDeck

/// SBrain 분석 이벤트 전송 (TelemetryDeck)
enum Analytics {
    /// TelemetryDeck 초기화 — 앱 시작 시 1회 호출
    static func initialize() {
        let config = TelemetryDeck.Config(appID: "44EA3837-B089-461D-B625-E4E48D4EDF4B")
        TelemetryDeck.initialize(config: config)
    }

    // MARK: - App Lifecycle

    static func appLaunch() {
        #if os(iOS)
        let platform = "iOS"
        #else
        let platform = "macOS"
        #endif
        TelemetryDeck.signal("app.launch", parameters: ["platform": platform])
    }

    // MARK: - View Tracking

    static func viewBrainMap(neuronCount: Int) {
        TelemetryDeck.signal("view.brainmap", parameters: ["neuronCount": "\(neuronCount)"])
    }

    static func viewBrainMapDuration(seconds: Int) {
        TelemetryDeck.signal("view.brainmap.duration", parameters: ["seconds": "\(seconds)"])
    }

    static func viewList() {
        TelemetryDeck.signal("view.list")
    }

    static func viewSlack() {
        TelemetryDeck.signal("view.slack")
    }

    static func viewCalendar() {
        TelemetryDeck.signal("view.calendar")
    }

    // MARK: - Actions

    static func searchRecall(resultCount: Int) {
        TelemetryDeck.signal("search.recall", parameters: ["resultCount": "\(resultCount)"])
    }

    static func syncPush(noteCount: Int) {
        TelemetryDeck.signal("sync.push", parameters: ["noteCount": "\(noteCount)"])
    }

    static func syncError(_ error: String) {
        TelemetryDeck.signal("sync.error", parameters: ["error": error])
    }

    static func authLogin() {
        #if os(iOS)
        let platform = "iOS"
        #else
        let platform = "macOS"
        #endif
        TelemetryDeck.signal("auth.login", parameters: ["platform": platform])
    }
}
