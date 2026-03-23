import Foundation
import SwiftUI

// MARK: - Slack Store

@MainActor
class SlackStore: ObservableObject {
    @Published var messages: [SlackMessage] = []
    @Published var channels: [SlackChannel] = []
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var isUserAuthenticated = false
    @Published var userName: String = ""
    @Published var errorMessage: String?
    @Published var selectedChannelId: String?

    private let api = APIClient.shared

    /// Check Slack connection status + user auth
    func checkStatus() async {
        do {
            let status = try await api.slackStatus()
            isConnected = status.connected
            errorMessage = nil
        } catch {
            isConnected = false
            errorMessage = "Slack 연결 상태 확인 실패"
        }

        // 사용자 인증 상태 확인
        do {
            let user = try await api.slackUser()
            isUserAuthenticated = user.authenticated
            userName = user.user?.name ?? ""
        } catch {
            isUserAuthenticated = false
        }
    }

    /// Slack OAuth 시작 (브라우저 열기)
    func startAuth() async {
        do {
            let authUrl = try await api.slackAuth()
            if let url = URL(string: authUrl) {
                NSWorkspace.shared.open(url)
            }
        } catch {
            errorMessage = "Slack 인증 URL 생성 실패"
        }
    }

    /// Scan Slack for actionable messages (AI triage)
    func scan() async {
        isScanning = true
        errorMessage = nil
        do {
            let scanned = try await api.slackScan()
            messages = scanned
        } catch {
            errorMessage = "스캔 실패: \(error.localizedDescription)"
        }
        isScanning = false
    }

    /// Send a reply to a Slack message
    func sendReply(messageId: String, channel: String, threadTs: String?, text: String) async {
        do {
            let ok = try await api.slackReply(
                messageId: messageId,
                channel: channel,
                threadTs: threadTs,
                text: text
            )
            if ok {
                // Remove the message from the list after successful reply
                messages.removeAll { $0.id == messageId }
            }
        } catch {
            errorMessage = "답변 전송 실패: \(error.localizedDescription)"
        }
    }

    /// Load available Slack channels
    func loadChannels() async {
        do {
            channels = try await api.slackChannels()
            errorMessage = nil
        } catch {
            errorMessage = "채널 목록 로드 실패"
        }
    }

    /// Dismiss a message (remove from list)
    func dismiss(messageId: String) {
        messages.removeAll { $0.id == messageId }
    }

    /// Filtered messages by selected channel
    var filteredMessages: [SlackMessage] {
        guard let channelId = selectedChannelId else { return messages }
        return messages.filter { $0.channel == channelId }
    }
}
