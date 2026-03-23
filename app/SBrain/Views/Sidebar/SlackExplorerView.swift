import SwiftUI

// MARK: - Slack Explorer View (Sidebar Panel)

struct SlackExplorerView: View {
    @EnvironmentObject var slackStore: SlackStore

    var body: some View {
        VStack(spacing: 0) {
            // Connection status
            connectionStatus

            Rectangle()
                .fill(SB.Colors.navy100)
                .frame(height: 1)

            if slackStore.isConnected {
                // Filter section
                filterSection

                Rectangle()
                    .fill(SB.Colors.navy100)
                    .frame(height: 1)

                // Channel list
                channelList
            } else {
                disconnectedState
            }
        }
    }

    // MARK: - Connection Status

    private var connectionStatus: some View {
        HStack(spacing: SB.Space.sm) {
            Circle()
                .fill(slackStore.isConnected ? SB.Colors.accentGreen : SB.Colors.accentRed)
                .frame(width: 6, height: 6)

            Text(slackStore.isConnected ? "연결됨" : "미연결")
                .font(SB.Font.caption())
                .foregroundStyle(SB.Colors.navy500)

            Spacer()

            // Refresh channels
            if slackStore.isConnected {
                Button(action: {
                    Task { await slackStore.loadChannels() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(SB.Colors.navy500)
                }
                .buttonStyle(.plain)
                .help("채널 새로고침")
            }
        }
        .padding(.horizontal, SB.Space.md)
        .padding(.vertical, SB.Space.sm)
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: SB.Space.xs) {
            Text("필터")
                .font(SB.Font.caption())
                .foregroundStyle(SB.Colors.navy500)
                .textCase(.uppercase)

            // All messages
            Button(action: { slackStore.selectedChannelId = nil }) {
                HStack(spacing: SB.Space.sm) {
                    Image(systemName: "tray.full")
                        .font(.system(size: 11))
                        .foregroundStyle(slackStore.selectedChannelId == nil ? SB.Colors.gold600 : SB.Colors.navy500)

                    Text("전체 메시지")
                        .font(SB.Font.bodySm())
                        .foregroundStyle(slackStore.selectedChannelId == nil ? SB.Colors.navy900 : SB.Colors.navy700)

                    Spacer()

                    Text("\(slackStore.messages.count)")
                        .font(SB.Font.monoSm())
                        .foregroundStyle(SB.Colors.navy300)
                }
                .padding(.horizontal, SB.Space.sm)
                .padding(.vertical, SB.Space.xs + 1)
                .background(
                    RoundedRectangle(cornerRadius: SB.Radius.sm)
                        .fill(slackStore.selectedChannelId == nil ? SB.Colors.gold100 : Color.clear)
                )
            }
            .buttonStyle(.plain)

            // Urgency filters
            urgencyFilterRow(label: "긴급", urgency: "high", color: SB.Colors.accentRed)
            urgencyFilterRow(label: "보통", urgency: "medium", color: SB.Colors.accentOrange)
            urgencyFilterRow(label: "낮음", urgency: "low", color: SB.Colors.accentGreen)
        }
        .padding(.horizontal, SB.Space.md)
        .padding(.vertical, SB.Space.sm)
    }

    private func urgencyFilterRow(label: String, urgency: String, color: Color) -> some View {
        let count = slackStore.messages.filter { $0.urgency == urgency }.count
        return HStack(spacing: SB.Space.sm) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(label)
                .font(SB.Font.caption())
                .foregroundStyle(SB.Colors.navy700)

            Spacer()

            Text("\(count)")
                .font(SB.Font.monoSm())
                .foregroundStyle(SB.Colors.navy300)
        }
        .padding(.horizontal, SB.Space.sm)
        .padding(.vertical, SB.Space.xs)
    }

    // MARK: - Channel List

    private var channelList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("채널")
                .font(SB.Font.caption())
                .foregroundStyle(SB.Colors.navy500)
                .textCase(.uppercase)
                .padding(.horizontal, SB.Space.md)
                .padding(.top, SB.Space.sm)
                .padding(.bottom, SB.Space.xs)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(slackStore.channels) { channel in
                        ChannelRow(
                            channel: channel,
                            isSelected: slackStore.selectedChannelId == channel.id,
                            messageCount: slackStore.messages.filter { $0.channel == channel.id }.count
                        ) {
                            if slackStore.selectedChannelId == channel.id {
                                slackStore.selectedChannelId = nil
                            } else {
                                slackStore.selectedChannelId = channel.id
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Disconnected State

    private var disconnectedState: some View {
        VStack(spacing: SB.Space.md) {
            Spacer().frame(height: SB.Space.xxl)

            Image(systemName: "number.square")
                .font(.system(size: 28))
                .foregroundStyle(SB.Colors.navy300)

            Text("Slack 미연결")
                .font(SB.Font.bodySm())
                .foregroundStyle(SB.Colors.navy500)

            Text("백엔드에서 Slack\n연동을 설정하세요")
                .font(SB.Font.caption())
                .foregroundStyle(SB.Colors.navy300)
                .multilineTextAlignment(.center)

            Button(action: {
                Task { await slackStore.checkStatus() }
            }) {
                Label("재확인", systemImage: "arrow.clockwise")
                    .font(SB.Font.caption())
            }
            .buttonStyle(SBGoldButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(SB.Space.md)
    }
}

// MARK: - Channel Row

private struct ChannelRow: View {
    let channel: SlackChannel
    let isSelected: Bool
    let messageCount: Int
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SB.Space.sm) {
                Image(systemName: "number")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? SB.Colors.gold600 : SB.Colors.navy500)

                Text(channel.name)
                    .font(SB.Font.bodySm())
                    .foregroundStyle(isSelected ? SB.Colors.navy900 : SB.Colors.navy700)
                    .lineLimit(1)

                Spacer()

                if messageCount > 0 {
                    Text("\(messageCount)")
                        .font(SB.Font.monoSm())
                        .foregroundStyle(SB.Colors.gold600)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(SB.Colors.gold100)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, SB.Space.md)
            .padding(.vertical, SB.Space.xs + 2)
            .background(
                RoundedRectangle(cornerRadius: SB.Radius.sm)
                    .fill(isSelected ? SB.Colors.gold100 : (isHovered ? SB.Colors.bgTertiary : Color.clear))
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
