import EventKit
import SwiftUI

@MainActor
@Observable
final class CalendarService {
    enum Access { case unknown, granted, denied }

    struct Event: Equatable {
        let title: String
        let start: Date
        let end: Date
        let color: Color
        let location: String?
        let isAllDay: Bool
    }

    private(set) var access: Access = .unknown
    private(set) var nextEvent: Event?
    /// True when the next event starts within 10 minutes or began less than 5 minutes ago.
    private(set) var isImminent = false
    /// Up to three of today's remaining events, all-day first.
    private(set) var todayEvents: [Event] = []

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            begin()
        case .notDetermined:
            requestAccess()
        default:
            access = .denied
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor in
                self?.access = granted ? .granted : .denied
                if granted { self?.begin() }
            }
        }
    }

    private func begin() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        guard access == .granted else { return }
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-12 * 3600),
            end: now.addingTimeInterval(24 * 3600),
            calendars: nil
        )
        let events = store.events(matching: predicate)
            .filter { $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
        let timed = events.first { !$0.isAllDay }
        let allDayToday = events.first { $0.isAllDay && $0.startDate <= now }
        // A timed event today wins; otherwise today's all-day event (e.g. a holiday); otherwise tomorrow's.
        let next: EKEvent?
        if let timed, Calendar.current.isDateInToday(timed.startDate) {
            next = timed
        } else {
            next = allDayToday ?? timed
        }

        func makeEvent(_ e: EKEvent) -> Event {
            Event(
                title: e.title ?? "Untitled",
                start: e.startDate,
                end: e.endDate,
                color: Color(cgColor: e.calendar.cgColor),
                location: e.location,
                isAllDay: e.isAllDay
            )
        }
        nextEvent = next.map(makeEvent)

        let today = events
            .filter { Calendar.current.isDateInToday($0.startDate) || $0.startDate <= now }
            .sorted { $0.isAllDay != $1.isAllDay ? $0.isAllDay : $0.startDate < $1.startDate }
            .prefix(3)
            .map(makeEvent)
        if today != todayEvents { todayEvents = Array(today) }
        if let e = nextEvent, !e.isAllDay {
            let untilStart = e.start.timeIntervalSince(now)
            isImminent = untilStart <= 600 && untilStart > -300
        } else {
            isImminent = false
        }
    }
}
