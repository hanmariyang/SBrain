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
    private var pollingTask: Task<Void, Never>?
    private var dismissedIds: Set<String> = []

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

        do {
            let user = try await api.slackUser()
            isUserAuthenticated = user.authenticated
            userName = user.user?.name ?? ""
        } catch {
            isUserAuthenticated = false
        }
    }

    /// Slack OAuth 시작 (브라우저 열기 + 완료 대기 폴링)
    func startAuth() async {
        do {
            let authUrl = try await api.slackAuth()
            if let url = URL(string: authUrl) {
                NSWorkspace.shared.open(url)
            }
            for _ in 0..<15 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                let user = try await api.slackUser()
                if user.authenticated {
                    isUserAuthenticated = true
                    userName = user.user?.name ?? ""
                    return
                }
            }
        } catch {
            errorMessage = "Slack 인증 실패"
        }
    }

    /// 5초 간격 자동 폴링 시작
    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                await fetchNewMessages()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    /// 폴링 중지
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// 서버에서 새 메시지 가져오기 (수동 스캔 대체)
    func fetchNewMessages() async {
        guard isConnected else { return }
        do {
            let scanned = try await api.slackScan()
            // 새 메시지만 추가 (기존 + 신규 합치기, dismissed 제외)
            for msg in scanned {
                if !dismissedIds.contains(msg.id) && !messages.contains(where: { $0.id == msg.id }) {
                    messages.append(msg)
                }
            }
            errorMessage = nil
        } catch {
            // 폴링 실패는 조용히 처리
        }
    }

    /// 수동 스캔 (기존 호환)
    func scan() async {
        isScanning = true
        errorMessage = nil
        await fetchNewMessages()
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
                messages.removeAll { $0.id == messageId }
                dismissedIds.insert(messageId)
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
        dismissedIds.insert(messageId)
    }

    /// Filtered messages by selected channel
    var filteredMessages: [SlackMessage] {
        guard let channelId = selectedChannelId else { return messages }
        return messages.filter { $0.channel == channelId }
    }
}
