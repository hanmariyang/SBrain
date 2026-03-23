import SwiftUI

// MARK: - Calendar Explorer View (Sidebar Panel)

struct CalendarExplorerView: View {
    @EnvironmentObject var calendarStore: CalendarStore

    private let calendar = Calendar.current
    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            if calendarStore.isAuthenticated {
                // Mini month header
                miniMonthHeader

                // Mini calendar grid
                miniCalendarGrid
                    .padding(.horizontal, SB.Space.sm)

                Rectangle()
                    .fill(SB.Colors.navy100)
                    .frame(height: 1)
                    .padding(.vertical, SB.Space.xs)

                // Today's events
                todayEventsList
            } else {
                unauthenticatedState
            }
        }
    }

    // MARK: - Mini Month Header

    private var miniMonthHeader: some View {
        HStack(spacing: SB.Space.sm) {
            Button(action: { navigateMonth(-1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SB.Colors.navy500)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(monthYearString)
                .font(SB.Font.caption())
                .foregroundStyle(SB.Colors.navy700)

            Spacer()

            Button(action: { navigateMonth(1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SB.Colors.navy500)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SB.Space.md)
        .padding(.vertical, SB.Space.sm)
    }

    // MARK: - Mini Calendar Grid

    private var miniCalendarGrid: some View {
        VStack(spacing: 0) {
            // Weekday headers
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(SB.Colors.navy300)
                        .frame(height: 18)
                }
            }

            // Day cells
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(daysInMonth, id: \.self) { date in
                    if let date = date {
                        MiniDayCell(
                            date: date,
                            isToday: calendar.isDateInToday(date),
                            isSelected: calendar.isDate(date, inSameDayAs: calendarStore.selectedDate),
                            hasEvents: !calendarStore.events(for: date).isEmpty
                        ) {
                            calendarStore.selectedDate = date
                        }
                    } else {
                        Color.clear
                            .frame(height: 24)
                    }
                }
            }
        }
    }

    // MARK: - Today's Events

    private var todayEventsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: SB.Space.xs) {
                Text(selectedDateLabel)
                    .font(SB.Font.caption())
                    .foregroundStyle(SB.Colors.navy500)
                    .textCase(.uppercase)

                Spacer()

                let count = calendarStore.eventsForSelectedDate.count
                if count > 0 {
                    Text("\(count)")
                        .font(SB.Font.monoSm())
                        .foregroundStyle(SB.Colors.gold600)
                }
            }
            .padding(.horizontal, SB.Space.md)
            .padding(.vertical, SB.Space.sm)

            ScrollView {
                LazyVStack(spacing: 2) {
                    let dayEvents = calendarStore.eventsForSelectedDate
                    if dayEvents.isEmpty {
                        VStack(spacing: SB.Space.sm) {
                            Spacer().frame(height: SB.Space.lg)
                            Image(systemName: "calendar")
                                .font(.system(size: 20))
                                .foregroundStyle(SB.Colors.navy300)
                            Text("일정 없음")
                                .font(SB.Font.caption())
                                .foregroundStyle(SB.Colors.navy500)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(dayEvents) { event in
                            MiniEventRow(event: event)
                        }
                    }
                }
                .padding(.horizontal, SB.Space.sm)
            }
        }
    }

    // MARK: - Unauthenticated State

    private var unauthenticatedState: some View {
        VStack(spacing: SB.Space.md) {
            Spacer().frame(height: SB.Space.xxl)

            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(SB.Colors.navy300)

            Text("Google Calendar\n연동 필요")
                .font(SB.Font.bodySm())
                .foregroundStyle(SB.Colors.navy500)
                .multilineTextAlignment(.center)

            Button(action: {
                Task { await calendarStore.startAuth() }
            }) {
                Label("연결", systemImage: "link")
                    .font(SB.Font.caption())
            }
            .buttonStyle(SBGoldButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(SB.Space.md)
    }

    // MARK: - Helpers

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM"
        return formatter.string(from: calendarStore.selectedDate)
    }

    private var selectedDateLabel: String {
        if calendar.isDateInToday(calendarStore.selectedDate) {
            return "오늘"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: calendarStore.selectedDate)
    }

    private func navigateMonth(_ offset: Int) {
        guard let newDate = calendar.date(byAdding: .month, value: offset, to: calendarStore.selectedDate) else { return }
        calendarStore.selectedDate = newDate
        Task { await calendarStore.loadCurrentMonth() }
    }

    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: calendarStore.selectedDate),
              let monthRange = calendar.range(of: .day, in: .month, for: calendarStore.selectedDate) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmpty = firstWeekday - 1

        var days: [Date?] = Array(repeating: nil, count: leadingEmpty)

        for day in monthRange {
            if let date = calendar.date(bySetting: .day, value: day, of: monthInterval.start) {
                days.append(date)
            }
        }

        let remainder = days.count % 7
        if remainder > 0 {
            days.append(contentsOf: Array(repeating: nil as Date?, count: 7 - remainder))
        }

        return days
    }
}

// MARK: - Mini Day Cell

private struct MiniDayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let hasEvents: Bool
    let action: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 10))
                    .foregroundStyle(textColor)

                if hasEvents {
                    Circle()
                        .fill(SB.Colors.gold600)
                        .frame(width: 3, height: 3)
                } else {
                    Spacer().frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isToday ? SB.Colors.gold600 : Color.clear, lineWidth: 1)
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

// MARK: - Mini Event Row

private struct MiniEventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: SB.Space.xs) {
            Rectangle()
                .fill(SB.Colors.gold600)
                .frame(width: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(SB.Font.caption())
                    .foregroundStyle(SB.Colors.navy900)
                    .lineLimit(1)

                if event.isAllDay {
                    Text("종일")
                        .font(.system(size: 9))
                        .foregroundStyle(SB.Colors.gold600)
                } else {
                    Text(formatTime(event.start))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(SB.Colors.navy500)
                }
            }

            Spacer()
        }
        .padding(.vertical, SB.Space.xs)
        .padding(.horizontal, SB.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: SB.Radius.sm)
                .fill(SB.Colors.bgTertiary.opacity(0.5))
        )
    }

    private func formatTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: isoString) else { return isoString }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        return timeFormatter.string(from: date)
    }
}
