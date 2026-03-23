import SwiftUI

// MARK: - Slack Agent View (Main Content Area)

struct SlackAgentView: View {
    @EnvironmentObject var slackStore: SlackStore
    @EnvironmentObject var calendarStore: CalendarStore

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: connection status + scan button
            slackTopBar

            Rectangle()
                .fill(SB.Colors.navy100)
                .frame(height: 1)

            // Message list
            if slackStore.filteredMessages.isEmpty {
                emptyState
            } else {
                messageList
            }
        }
        .background(SB.Colors.bgPrimary)
        .task {
            await slackStore.checkStatus()
            if slackStore.isConnected {
                await slackStore.loadChannels()
                slackStore.startPolling()
            }
        }
        .onDisappear {
            slackStore.stopPolling()
        }
    }

    // MARK: - Top Bar

    // 연결 상태는 ExplorerPanel(SlackExplorerView)에서 담당
    // 메인 영역은 스캔 + 메시지 카운트만 표시
    private var slackTopBar: some View {
        HStack(spacing: SB.Space.md) {
            Text("Slack 메시지")
                .font(SB.Font.titleSm())
                .foregroundStyle(SB.Colors.navy900)

            // Message count
            if !slackStore.filteredMessages.isEmpty {
                Text("\(slackStore.filteredMessages.count)")
                    .font(SB.Font.monoSm())
                    .foregroundStyle(SB.Colors.gold600)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(SB.Colors.gold100)
                    .clipShape(Capsule())
            }

            Spacer()

            // Error message
            if let error = slackStore.errorMessage {
                Text(error)
                    .font(SB.Font.caption())
                    .foregroundStyle(SB.Colors.accentRed)
                    .lineLimit(1)
            }

            // Scan button
            Button(action: {
                Task { await slackStore.scan() }
            }) {
                HStack(spacing: SB.Space.xs) {
                    if slackStore.isScanning {
                        ProgressView()
                            .scaleEffect(0.5)
                            .tint(SB.Colors.gold600)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                    }
                    Text("스캔")
                        .font(SB.Font.bodySm())
                }
                .foregroundStyle(slackStore.isScanning ? SB.Colors.navy500 : SB.Colors.gold600)
                .padding(.horizontal, SB.Space.md)
                .padding(.vertical, SB.Space.xs)
                .background(SB.Colors.gold100)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(slackStore.isScanning || !slackStore.isConnected)
        }
        .padding(.horizontal, SB.Space.lg)
        .padding(.vertical, SB.Space.md)
        .background(SB.Colors.bgElevated)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: SB.Space.md) {
                ForEach(slackStore.filteredMessages) { message in
                    SlackMessageCard(message: message)
                }
            }
            .padding(SB.Space.lg)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: SB.Space.lg) {
            Spacer()

            if slackStore.isConnected {
                Image(systemName: "tray")
                    .font(.system(size: 48))
                    .foregroundStyle(SB.Colors.navy300)

                Text("처리할 메시지가 없습니다")
                    .font(SB.Font.titleMd())
                    .foregroundStyle(SB.Colors.navy500)

                Text("스캔 버튼을 눌러 Slack 메시지를 분석하세요")
                    .font(SB.Font.bodySm())
                    .foregroundStyle(SB.Colors.navy300)

                Button(action: {
                    Task { await slackStore.scan() }
                }) {
                    Label("Slack 스캔", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(SBGoldButtonStyle())
                .disabled(slackStore.isScanning)
            } else {
                Image(systemName: "arrow.left")
                    .font(.system(size: 24))
                    .foregroundStyle(SB.Colors.navy300)

                Text("사이드바에서 Slack 연결 상태를 확인하세요")
                    .font(SB.Font.bodySm())
                    .foregroundStyle(SB.Colors.navy500)
            }

            Spacer()
        }
    }
}

// MARK: - Slack Message Card

struct SlackMessageCard: View {
    @EnvironmentObject var slackStore: SlackStore
    @EnvironmentObject var calendarStore: CalendarStore
    let message: SlackMessage

    @State private var editedReply: String = ""
    @State private var isReplying = false
    @State private var isCreatingEvent = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: SB.Space.md) {
            // Header: urgency badge + sender + channel
            HStack(spacing: SB.Space.sm) {
                urgencyBadge

                Text(message.userName)
                    .font(SB.Font.titleSm())
                    .foregroundStyle(SB.Colors.navy900)

                Text("in #\(message.channelName)")
                    .font(SB.Font.caption())
                    .foregroundStyle(SB.Colors.navy500)

                Spacer()

                Text(formatTimestamp(message.timestamp))
                    .font(SB.Font.monoSm())
                    .foregroundStyle(SB.Colors.navy300)
            }

            // Summary or original text
            if let summary = message.summary, !summary.isEmpty {
                Text(summary)
                    .font(SB.Font.bodyMd())
                    .foregroundStyle(SB.Colors.navy700)
                    .lineLimit(3)
            } else {
                Text(message.text)
                    .font(SB.Font.bodySm())
                    .foregroundStyle(SB.Colors.navy700)
                    .lineLimit(4)
            }

            // Calendar event suggestion
            if let event = message.calendarEvent {
                calendarSuggestionBanner(event)
            }

            // Draft reply section
            if let draft = message.draftReply, !draft.isEmpty {
                draftReplySection(draft: draft)
            }

            // Action buttons
            actionButtons
        }
        .padding(SB.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: SB.Radius.md)
                .fill(SB.Colors.bgElevated)
                .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SB.Radius.md)
                .stroke(urgencyBorderColor, lineWidth: isHovered ? 1.5 : 0.5)
        )
        .onHover { isHovered = $0 }
        .onAppear {
            editedReply = message.draftReply ?? ""
        }
    }

    // MARK: - Urgency Badge

    private var urgencyBadge: some View {
        Text(urgencyLabel)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, SB.Space.sm)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(urgencyColor)
            )
    }

    private var urgencyLabel: String {
        switch message.urgency {
        case "high": return "긴급"
        case "medium": return "보통"
        case "low": return "낮음"
        default: return "보통"
        }
    }

    private var urgencyColor: Color {
        switch message.urgency {
        case "high": return SB.Colors.accentRed
        case "medium": return SB.Colors.accentOrange
        case "low": return SB.Colors.accentGreen
        default: return SB.Colors.navy500
        }
    }

    private var urgencyBorderColor: Color {
        switch message.urgency {
        case "high": return SB.Colors.accentRed.opacity(0.3)
        case "medium": return SB.Colors.accentOrange.opacity(0.2)
        default: return SB.Colors.navy100
        }
    }

    // MARK: - Calendar Suggestion

    private func calendarSuggestionBanner(_ event: CalendarEventSuggestion) -> some View {
        HStack(spacing: SB.Space.sm) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 12))
                .foregroundStyle(SB.Colors.accentBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(SB.Font.bodySm())
                    .foregroundStyle(SB.Colors.navy900)
                HStack(spacing: SB.Space.sm) {
                    Text(event.datetime)
                        .font(SB.Font.monoSm())
                        .foregroundStyle(SB.Colors.navy500)
                    Text("\(event.durationMin)분")
                        .font(SB.Font.caption())
                        .foregroundStyle(SB.Colors.navy500)
                }
            }

            Spacer()
        }
        .padding(SB.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: SB.Radius.sm)
                .fill(SB.Colors.accentBlue.opacity(0.08))
        )
    }

    // MARK: - Draft Reply

    private func draftReplySection(draft: String) -> some View {
        VStack(alignment: .leading, spacing: SB.Space.xs) {
            Text("AI 답변 초안")
                .font(SB.Font.caption())
                .foregroundStyle(SB.Colors.gold600)

            TextEditor(text: $editedReply)
                .font(SB.Font.bodySm())
                .foregroundStyle(SB.Colors.navy700)
                .scrollContentBackground(.hidden)
                .padding(SB.Space.sm)
                .frame(minHeight: 60, maxHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: SB.Radius.sm)
                        .fill(SB.Colors.bgSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SB.Radius.sm)
                        .stroke(SB.Colors.navy100, lineWidth: 1)
                )
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: SB.Space.md) {
            // Send reply
            if message.actionType == "reply" || message.actionType == "both" || message.draftReply != nil {
                Button(action: { sendReply() }) {
                    HStack(spacing: SB.Space.xs) {
                        if isReplying {
                            ProgressView()
                                .scaleEffect(0.4)
                                .tint(.white)
                        }
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10))
                        Text("답변 발송")
                            .font(SB.Font.caption())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, SB.Space.md)
                    .padding(.vertical, SB.Space.xs + 2)
                    .background(
                        Capsule().fill(SB.Colors.gold600)
                    )
                }
                .buttonStyle(.plain)
                .disabled(editedReply.trimmingCharacters(in: .whitespaces).isEmpty || isReplying)
            }

            // Create calendar event
            if message.actionType == "calendar" || message.actionType == "both", message.calendarEvent != nil {
                Button(action: { createCalendarEvent() }) {
                    HStack(spacing: SB.Space.xs) {
                        if isCreatingEvent {
                            ProgressView()
                                .scaleEffect(0.4)
                                .tint(SB.Colors.accentBlue)
                        }
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 10))
                        Text("일정 등록")
                            .font(SB.Font.caption())
                    }
                    .foregroundStyle(SB.Colors.accentBlue)
                    .padding(.horizontal, SB.Space.md)
                    .padding(.vertical, SB.Space.xs + 2)
                    .background(
                        Capsule()
                            .fill(SB.Colors.accentBlue.opacity(0.1))
                    )
                    .overlay(
                        Capsule().stroke(SB.Colors.accentBlue.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isCreatingEvent)
            }

            Spacer()

            // Dismiss
            Button(action: { slackStore.dismiss(messageId: message.id) }) {
                HStack(spacing: SB.Space.xs) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                    Text("무시")
                        .font(SB.Font.caption())
                }
                .foregroundStyle(SB.Colors.navy500)
                .padding(.horizontal, SB.Space.md)
                .padding(.vertical, SB.Space.xs + 2)
                .background(
                    Capsule()
                        .fill(SB.Colors.bgTertiary)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func sendReply() {
        isReplying = true
        Task {
            await slackStore.sendReply(
                messageId: message.id,
                channel: message.channel,
                threadTs: message.threadTs,
                text: editedReply
            )
            isReplying = false
        }
    }

    private func createCalendarEvent() {
        guard let event = message.calendarEvent else { return }
        isCreatingEvent = true
        Task {
            // Parse datetime and create end time from duration
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            let startDate = isoFormatter.date(from: event.datetime) ?? Date()
            let endDate = startDate.addingTimeInterval(TimeInterval(event.durationMin * 60))

            await calendarStore.createEvent(
                title: event.title,
                start: isoFormatter.string(from: startDate),
                end: isoFormatter.string(from: endDate),
                attendees: event.attendees
            )
            isCreatingEvent = false
        }
    }

    private func formatTimestamp(_ ts: String) -> String {
        // Slack timestamps are Unix epoch with decimal
        guard let dotIndex = ts.firstIndex(of: "."),
              let epoch = Double(ts[ts.startIndex..<dotIndex]) else {
            return ts
        }
        let date = Date(timeIntervalSince1970: epoch)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
