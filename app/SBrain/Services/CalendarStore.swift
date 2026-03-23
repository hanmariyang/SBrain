import Foundation
import SwiftUI
import AppKit

// MARK: - Calendar Store

@MainActor
class CalendarStore: ObservableObject {
    @Published var events: [CalendarEvent] = []
    @Published var isAuthenticated = false
    @Published var selectedDate = Date()
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient.shared

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Check Google Calendar authentication status
    func checkAuth() async {
        do {
            let status = try await api.calendarStatus()
            isAuthenticated = status.authenticated
            errorMessage = nil
        } catch {
            isAuthenticated = false
            errorMessage = "인증 상태 확인 실패"
        }
    }

    /// Start OAuth flow — opens browser
    func startAuth() async {
        do {
            let authUrl = try await api.calendarAuth()
            if let url = URL(string: authUrl) {
                NSWorkspace.shared.open(url)
            }
        } catch {
            errorMessage = "인증 시작 실패: \(error.localizedDescription)"
        }
    }

    /// Load events for a date range
    func loadEvents(start: Date, end: Date) async {
        isLoading = true
        errorMessage = nil
        do {
            let startStr = Self.isoFormatter.string(from: start)
            let endStr = Self.isoFormatter.string(from: end)
            events = try await api.calendarEvents(start: startStr, end: endStr)
        } catch {
            errorMessage = "일정 로드 실패: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Load events for the currently selected month
    func loadCurrentMonth() async {
        let calendar = Foundation.Calendar.current
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)),
              let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) else { return }
        await loadEvents(start: start, end: end)
    }

    /// Create a new event
    func createEvent(title: String, start: String, end: String, description: String? = nil, location: String? = nil, attendees: [String]? = nil) async {
        do {
            let event = try await api.calendarCreateEvent(
                title: title, start: start, end: end,
                description: description, location: location, attendees: attendees
            )
            events.append(event)
            events.sort { $0.start < $1.start }
        } catch {
            errorMessage = "일정 생성 실패: \(error.localizedDescription)"
        }
    }

    /// Delete an event
    func deleteEvent(id: String) async {
        do {
            try await api.calendarDeleteEvent(id: id)
            events.removeAll { $0.id == id }
        } catch {
            errorMessage = "일정 삭제 실패: \(error.localizedDescription)"
        }
    }

    /// Events for the selected date
    var eventsForSelectedDate: [CalendarEvent] {
        let dateStr = Self.displayDateFormatter.string(from: selectedDate)
        return events.filter { $0.start.hasPrefix(dateStr) }
    }

    /// Events for a given date
    func events(for date: Date) -> [CalendarEvent] {
        let dateStr = Self.displayDateFormatter.string(from: date)
        return events.filter { $0.start.hasPrefix(dateStr) }
    }
}
