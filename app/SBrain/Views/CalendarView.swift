import SwiftUI

// MARK: - Calendar View (Main Content Area)

struct CalendarView: View {
    @EnvironmentObject var calendarStore: CalendarStore
    @State private var showCreateSheet = false

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            if calendarStore.isAuthenticated {
                authenticatedContent
            } else {
                // 인증 화면은 ExplorerPanel(CalendarExplorerView)에서 담당
                unauthenticatedState
            }
        }
        .background(SB.Colors.bgPrimary)
        .task {
            if calendarStore.isAuthenticated {
                await calendarStore.loadCurrentMonth()
            }
        }
    }

    // MARK: - Authenticated Content
    // 캘린더 그리드는 ExplorerPanel(CalendarExplorerView)에서 담당
    // 메인 영역은 선택된 날짜의 일정 상세만 표시

    private var authenticatedContent: some View {
        VStack(spacing: 0) {
            // Selected date header with create button
            HStack(spacing: SB.Space.md) {
                Text(selectedDateString)
                    .font(SB.Font.titleMd())
                    .foregroundStyle(SB.Colors.navy900)

                let count = calendarStore.eventsForSelectedDate.count
                if count > 0 {
                    Text("\(count)")
                        .font(SB.Font.monoSm())
                        .foregroundStyle(SB.Colors.gold600)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(SB.Colors.gold100)
                        .clipShape(Capsule())
                }

                Spacer()

                Button(action: { calendarStore.selectedDate = Date() }) {
                    Text("오늘")
                        .font(SB.Font.bodySm())
                        .foregroundStyle(SB.Colors.gold600)
                        .padding(.horizontal, SB.Space.md)
                        .padding(.vertical, SB.Space.xs)
                        .background(SB.Colors.gold100)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: { showCreateSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(SB.Colors.gold600)
                }
                .buttonStyle(.plain)
                .help("일정 추가")

                if calendarStore.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(SB.Colors.gold600)
                }
            }
            .padding(.horizontal, SB.Space.lg)
            .padding(.vertical, SB.Space.md)
            .background(SB.Colors.bgElevated)
            .sheet(isPresented: $showCreateSheet) {
                CalendarCreateEventSheet(isPresented: $showCreateSheet)
            }

            Rectangle()
                .fill(SB.Colors.navy100)
                .frame(height: 1)

            // Events list
            ScrollView {
                LazyVStack(spacing: SB.Space.sm) {
                    let dayEvents = calendarStore.eventsForSelectedDate
                    if dayEvents.isEmpty {
                        emptyEventsState
                    } else {
                        ForEach(dayEvents) { event in
                            CalendarEventCard(event: event)
                        }
                    }
                }
                .padding(.horizontal, SB.Space.lg)
                .padding(.vertical, SB.Space.md)
            }
        }
    }

    // monthHeader, calendarGrid, selectedDateEventsSection — ExplorerPanel(CalendarExplorerView)로 이전됨

    // MARK: - Empty Events State

    private var emptyEventsState: some View {
        VStack(spacing: SB.Space.md) {
            Spacer().frame(height: SB.Space.xl)

            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 32))
                .foregroundStyle(SB.Colors.navy300)

            Text("일정이 없습니다")
                .font(SB.Font.bodySm())
                .foregroundStyle(SB.Colors.navy500)

            Button(action: { showCreateSheet = true }) {
                Label("일정 추가", systemImage: "plus")
                    .font(SB.Font.bodySm())
            }
            .buttonStyle(SBGoldButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(SB.Space.lg)
    }

    // MARK: - Unauthenticated State

    private var unauthenticatedState: some View {
        VStack(spacing: SB.Space.lg) {
            Spacer()

            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(
                    .linearGradient(
                        colors: [SB.Colors.navy700, SB.Colors.gold600],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.4)

            Text("Google Calendar 연동")
                .font(SB.Font.titleMd())
                .foregroundStyle(SB.Colors.navy900)

            Text("Google 계정을 연결하여\n캘린더 일정을 SBrain에서 관리하세요")
                .font(SB.Font.bodySm())
                .foregroundStyle(SB.Colors.navy500)
                .multilineTextAlignment(.center)

            Button(action: {
                Task { await calendarStore.startAuth() }
            }) {
                Label("Google 계정 연결", systemImage: "link.badge.plus")
            }
            .buttonStyle(SBGoldButtonStyle())

            if let error = calendarStore.errorMessage {
                Text(error)
                    .font(SB.Font.caption())
                    .foregroundStyle(SB.Colors.accentRed)
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private var selectedDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일 (E)"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: calendarStore.selectedDate)
    }

}

// MARK: - Calendar Day Cell

struct CalendarDayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let eventCount: Int
    let action: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(SB.Font.bodySm())
                    .foregroundStyle(textColor)

                if eventCount > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<min(eventCount, 3), id: \.self) { _ in
                            Circle()
                                .fill(SB.Colors.gold600)
                                .frame(width: 4, height: 4)
                        }
                    }
                } else {
                    Spacer().frame(height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: SB.Radius.sm)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SB.Radius.sm)
                    .stroke(isToday ? SB.Colors.gold600 : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var textColor: Color {
        if isSelected { return SB.Colors.navy900 }
        if isToday { return SB.Colors.gold600 }
        return SB.Colors.navy700
    }

    private var backgroundColor: Color {
        if isSelected { return SB.Colors.gold100 }
        return Color.clear
    }
}

// MARK: - Calendar Event Card

struct CalendarEventCard: View {
    @EnvironmentObject var calendarStore: CalendarStore
    let event: CalendarEvent
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: SB.Space.md) {
            // Time indicator
            Rectangle()
                .fill(SB.Colors.gold600)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            VStack(alignment: .leading, spacing: SB.Space.xs) {
                Text(event.title)
                    .font(SB.Font.titleSm())
                    .foregroundStyle(SB.Colors.navy900)
                    .lineLimit(1)

                HStack(spacing: SB.Space.sm) {
                    if event.isAllDay {
                        Text("종일")
                            .font(SB.Font.caption())
                            .foregroundStyle(SB.Colors.gold600)
                    } else {
                        Text(formatTimeRange(start: event.start, end: event.end))
                            .font(SB.Font.monoSm())
                            .foregroundStyle(SB.Colors.navy500)
                    }

                    if let location = event.location, !location.isEmpty {
                        Image(systemName: "mappin")
                            .font(.system(size: 9))
                            .foregroundStyle(SB.Colors.navy300)
                        Text(location)
                            .font(SB.Font.caption())
                            .foregroundStyle(SB.Colors.navy500)
                            .lineLimit(1)
                    }
                }

                if let attendees = event.attendees, !attendees.isEmpty {
                    HStack(spacing: SB.Space.xs) {
                        Image(systemName: "person.2")
                            .font(.system(size: 9))
                            .foregroundStyle(SB.Colors.navy300)
                        Text(attendees.joined(separator: ", "))
                            .font(SB.Font.caption())
                            .foregroundStyle(SB.Colors.navy500)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Delete button on hover
            if isHovered {
                Button(action: {
                    Task { await calendarStore.deleteEvent(id: event.id) }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(SB.Colors.accentRed)
                }
                .buttonStyle(.plain)
                .help("일정 삭제")
            }
        }
        .padding(SB.Space.md)
        .background(
            RoundedRectangle(cornerRadius: SB.Radius.md)
                .fill(SB.Colors.bgElevated)
                .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
        )
        .onHover { isHovered = $0 }
    }

    private func formatTimeRange(start: String, end: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let startDate = formatter.date(from: start)
        let endDate = formatter.date(from: end)

        if let s = startDate, let e = endDate {
            return "\(timeFormatter.string(from: s)) - \(timeFormatter.string(from: e))"
        }
        return start
    }
}

// MARK: - Calendar Create Event Sheet

struct CalendarCreateEventSheet: View {
    @EnvironmentObject var calendarStore: CalendarStore
    @Binding var isPresented: Bool

    @State private var title = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600)
    @State private var eventDescription = ""
    @State private var location = ""
    @State private var isAllDay = false
    @FocusState private var isTitleFocused: Bool

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    var body: some View {
        VStack(spacing: SB.Space.lg) {
            // Header
            Text("새 일정 만들기")
                .font(SB.Font.titleMd())
                .foregroundStyle(SB.Colors.navy900)

            // Title
            VStack(alignment: .leading, spacing: SB.Space.xs) {
                Text("제목")
                    .font(SB.Font.caption())
                    .foregroundStyle(SB.Colors.navy500)
                TextField("일정 제목", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTitleFocused)
            }

            // All day toggle
            Toggle("종일", isOn: $isAllDay)
                .font(SB.Font.bodySm())
                .foregroundStyle(SB.Colors.navy700)
                .toggleStyle(.switch)
                .tint(SB.Colors.gold600)

            // Date pickers
            HStack(spacing: SB.Space.md) {
                VStack(alignment: .leading, spacing: SB.Space.xs) {
                    Text("시작")
                        .font(SB.Font.caption())
                        .foregroundStyle(SB.Colors.navy500)
                    DatePicker("", selection: $startDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: SB.Space.xs) {
                    Text("종료")
                        .font(SB.Font.caption())
                        .foregroundStyle(SB.Colors.navy500)
                    DatePicker("", selection: $endDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                        .labelsHidden()
                }
            }

            // Location
            VStack(alignment: .leading, spacing: SB.Space.xs) {
                Text("장소")
                    .font(SB.Font.caption())
                    .foregroundStyle(SB.Colors.navy500)
                TextField("장소 (선택)", text: $location)
                    .textFieldStyle(.roundedBorder)
            }

            // Description
            VStack(alignment: .leading, spacing: SB.Space.xs) {
                Text("설명")
                    .font(SB.Font.caption())
                    .foregroundStyle(SB.Colors.navy500)
                TextField("설명 (선택)", text: $eventDescription)
                    .textFieldStyle(.roundedBorder)
            }

            // Buttons
            HStack(spacing: SB.Space.md) {
                Button("취소") { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Button("만들기") { createEvent() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(SB.Space.xl)
        .frame(width: 400)
        .onAppear { isTitleFocused = true }
    }

    private func createEvent() {
        let startStr = Self.isoFormatter.string(from: startDate)
        let endStr = Self.isoFormatter.string(from: endDate)
        Task {
            await calendarStore.createEvent(
                title: title,
                start: startStr,
                end: endStr,
                description: eventDescription.isEmpty ? nil : eventDescription,
                location: location.isEmpty ? nil : location
            )
            isPresented = false
        }
    }
}
