import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    #if os(macOS)
    @EnvironmentObject var backendManager: BackendManager
    #endif
    @EnvironmentObject var slackStore: SlackStore
    @EnvironmentObject var calendarStore: CalendarStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("설정")
                    .font(SB.Font.titleMd())
                    .foregroundStyle(SB.Colors.navy900)

                Spacer()

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(SB.Colors.navy300)
                }
                .buttonStyle(.plain)
            }
            .padding(SB.Space.lg)

            Rectangle()
                .fill(SB.Colors.navy100)
                .frame(height: 1)

            ScrollView {
                VStack(spacing: SB.Space.lg) {
                    // Backend status
                    #if os(macOS)
                    settingsSection(title: "백엔드", icon: "server.rack") {
                        settingsRow(label: "상태", value: backendManager.isRunning ? "실행 중" : "중지됨",
                                    statusColor: backendManager.isRunning ? SB.Colors.accentGreen : SB.Colors.accentRed)
                        settingsRow(label: "포트", value: "8765")
                    }
                    #endif

                    // Slack connection
                    settingsSection(title: "Slack 연동", icon: "number.square") {
                        settingsRow(label: "상태", value: slackStore.isConnected ? "연결됨" : "미연결",
                                    statusColor: slackStore.isConnected ? SB.Colors.accentGreen : SB.Colors.accentRed)

                        if slackStore.isConnected {
                            settingsRow(label: "채널 수", value: "\(slackStore.channels.count)개")
                        }

                        HStack {
                            Text("연결 확인")
                                .font(SB.Font.bodySm())
                                .foregroundStyle(SB.Colors.navy700)
                            Spacer()
                            Button(action: {
                                Task { await slackStore.checkStatus() }
                            }) {
                                Text("새로고침")
                                    .font(SB.Font.caption())
                                    .foregroundStyle(SB.Colors.gold600)
                                    .padding(.horizontal, SB.Space.md)
                                    .padding(.vertical, SB.Space.xs)
                                    .background(SB.Colors.gold100)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Google Calendar
                    settingsSection(title: "Google Calendar", icon: "calendar") {
                        settingsRow(label: "상태", value: calendarStore.isAuthenticated ? "인증됨" : "미인증",
                                    statusColor: calendarStore.isAuthenticated ? SB.Colors.accentGreen : SB.Colors.accentRed)

                        if !calendarStore.isAuthenticated {
                            HStack {
                                Text("Google 계정 연결")
                                    .font(SB.Font.bodySm())
                                    .foregroundStyle(SB.Colors.navy700)
                                Spacer()
                                Button(action: {
                                    Task { await calendarStore.startAuth() }
                                }) {
                                    Text("연결")
                                        .font(SB.Font.caption())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, SB.Space.md)
                                        .padding(.vertical, SB.Space.xs)
                                        .background(SB.Colors.gold600)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // App info
                    settingsSection(title: "앱 정보", icon: "info.circle") {
                        settingsRow(label: "버전", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                        settingsRow(label: "빌드", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-")
                    }
                }
                .padding(SB.Space.lg)
            }
        }
        .frame(width: 420, height: 500)
        .background(SB.Colors.bgPrimary)
    }

    // MARK: - Section Builder

    private func settingsSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            HStack(spacing: SB.Space.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(SB.Colors.gold600)
                Text(title)
                    .font(SB.Font.titleSm())
                    .foregroundStyle(SB.Colors.navy900)
            }

            VStack(spacing: SB.Space.sm) {
                content()
            }
            .padding(SB.Space.md)
            .background(
                RoundedRectangle(cornerRadius: SB.Radius.md)
                    .fill(SB.Colors.bgElevated)
            )
        }
    }

    private func settingsRow(label: String, value: String, statusColor: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(SB.Font.bodySm())
                .foregroundStyle(SB.Colors.navy700)

            Spacer()

            HStack(spacing: SB.Space.xs) {
                if let color = statusColor {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
                Text(value)
                    .font(SB.Font.monoSm())
                    .foregroundStyle(SB.Colors.navy500)
            }
        }
    }
}
