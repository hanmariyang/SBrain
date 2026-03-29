import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    #if os(macOS)
    @EnvironmentObject var backendManager: BackendManager
    #endif
    @EnvironmentObject var slackStore: SlackStore
    @EnvironmentObject var calendarStore: CalendarStore
    @EnvironmentObject var syncManager: SyncManager
    @EnvironmentObject var noteStore: NoteStore
    @Binding var isPresented: Bool

    @State private var cloudUsername = ""
    @State private var cloudPassword = ""
    @State private var cloudLoginError: String?
    @State private var isLoggingIn = false

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

                    // Cloud Sync
                    settingsSection(title: "클라우드 동기화", icon: "icloud.and.arrow.up") {
                        settingsRow(
                            label: "상태",
                            value: syncManager.isCloudAuthenticated ? "연결됨" : "미연결",
                            statusColor: syncManager.isCloudAuthenticated ? SB.Colors.accentGreen : SB.Colors.accentRed
                        )

                        if syncManager.isCloudAuthenticated {
                            if let lastSync = syncManager.lastSyncAt {
                                settingsRow(label: "마지막 동기화", value: Self.timeAgo(lastSync))
                            }

                            if syncManager.isSyncing {
                                HStack {
                                    Text("동기화 중...")
                                        .font(SB.Font.bodySm())
                                        .foregroundStyle(SB.Colors.navy700)
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(0.6)
                                }
                            }

                            HStack {
                                Button(action: {
                                    Task { await syncManager.fullSync(projects: noteStore.projects) }
                                }) {
                                    Text("지금 동기화")
                                        .font(SB.Font.caption())
                                        .foregroundStyle(SB.Colors.gold600)
                                        .padding(.horizontal, SB.Space.md)
                                        .padding(.vertical, SB.Space.xs)
                                        .background(SB.Colors.gold100)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button(action: { syncManager.logout() }) {
                                    Text("로그아웃")
                                        .font(SB.Font.caption())
                                        .foregroundStyle(SB.Colors.accentRed)
                                }
                                .buttonStyle(.plain)
                            }

                            if let error = syncManager.syncError {
                                Text(error)
                                    .font(SB.Font.caption())
                                    .foregroundStyle(SB.Colors.accentRed)
                            }
                        } else {
                            // 로그인 폼
                            VStack(spacing: SB.Space.sm) {
                                TextField("Username", text: $cloudUsername)
                                    .textFieldStyle(.roundedBorder)
                                    .font(SB.Font.bodySm())

                                SecureField("Password", text: $cloudPassword)
                                    .textFieldStyle(.roundedBorder)
                                    .font(SB.Font.bodySm())

                                if let error = cloudLoginError {
                                    Text(error)
                                        .font(SB.Font.caption())
                                        .foregroundStyle(SB.Colors.accentRed)
                                }

                                Button(action: {
                                    isLoggingIn = true
                                    cloudLoginError = nil
                                    Task {
                                        do {
                                            try await syncManager.login(username: cloudUsername, password: cloudPassword)
                                            // 로그인 성공 → 즉시 전체 동기화
                                            await syncManager.fullSync(projects: noteStore.projects)
                                        } catch {
                                            cloudLoginError = "로그인 실패"
                                        }
                                        isLoggingIn = false
                                    }
                                }) {
                                    HStack {
                                        if isLoggingIn {
                                            ProgressView()
                                                .scaleEffect(0.6)
                                        }
                                        Text("클라우드 연결")
                                            .font(SB.Font.caption())
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, SB.Space.md)
                                    .padding(.vertical, SB.Space.xs)
                                    .background(SB.Colors.gold600)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(cloudUsername.isEmpty || cloudPassword.isEmpty || isLoggingIn)
                            }
                        }
                    }

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

    private static func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "방금 전" }
        if seconds < 3600 { return "\(seconds / 60)분 전" }
        if seconds < 86400 { return "\(seconds / 3600)시간 전" }
        return "\(seconds / 86400)일 전"
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
