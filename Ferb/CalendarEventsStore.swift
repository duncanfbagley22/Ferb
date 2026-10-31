import EventKit
import Foundation
import Observation
import SwiftUI

/// One calendar event as the Plan view needs it, clipped to a single day.
struct DayEvent: Identifiable {
    let id: String
    let title: String
    let isAllDay: Bool
    /// Minutes since midnight on the day being shown (a multi-day event is clipped to it).
    let startMinutes: Int
    let endMinutes: Int
    let color: Color
}

struct CalendarInfo: Identifiable {
    let id: String
    let title: String
}

/// Calendars grouped by the account they belong to (iCloud, Google, Subscribed...).
struct CalendarGroup: Identifiable {
    let title: String
    let calendars: [CalendarInfo]

    var id: String { title }
}

/// Read-only access to the events in the phone's calendars. It never creates, changes or
/// deletes anything. Which calendars are shown is remembered on this phone as the list of
/// ones you've hidden, so a calendar you add later appears by default.
@Observable
final class CalendarEventsStore {
    static let shared = CalendarEventsStore()

    private static let hiddenKey = "planHiddenCalendarIDs"

    private let store = EKEventStore()
    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    /// Bumped whenever the Calendar app's data changes, so screens showing events refresh.
    private(set) var revision = 0
    private(set) var hiddenIDs: Set<String>

    private init() {
        hiddenIDs = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? [])
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.revision += 1 }
        }
    }

    // MARK: - Permission

    var isAuthorized: Bool { status == .fullAccess }
    var canAsk: Bool { status == .notDetermined }

    func refreshStatus() {
        status = EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        refreshStatus()
        revision += 1
    }

    // MARK: - Calendars

    var groups: [CalendarGroup] {
        guard isAuthorized else { return [] }
        let all = store.calendars(for: .event)
        let bySource = Dictionary(grouping: all) { $0.source?.title ?? "Other" }
        return bySource
            .map { source, calendars in
                CalendarGroup(
                    title: source,
                    calendars: calendars
                        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                        .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title) }
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func isHidden(_ calendarID: String) -> Bool {
        hiddenIDs.contains(calendarID)
    }

    func setHidden(_ calendarID: String, hidden: Bool) {
        if hidden {
            hiddenIDs.insert(calendarID)
        } else {
            hiddenIDs.remove(calendarID)
        }
        UserDefaults.standard.set(Array(hiddenIDs), forKey: Self.hiddenKey)
    }

    // MARK: - Events

    /// The day's events from the calendars you haven't hidden: all-day ones first, then by
    /// start time. Cancelled events and ones you've declined are left out.
    func events(on day: Date) -> [DayEvent] {
        guard isAuthorized else { return [] }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let visible = store.calendars(for: .event).filter { !hiddenIDs.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { return [] }

        func minutes(_ date: Date) -> Int {
            if date <= dayStart { return 0 }
            if date >= dayEnd { return 24 * 60 }
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }

        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: visible)
        return store.events(matching: predicate)
            .compactMap { event -> DayEvent? in
                if event.status == .canceled { return nil }
                if event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) == true {
                    return nil
                }
                let title = (event.title ?? "").trimmingCharacters(in: .whitespaces)
                return DayEvent(
                    id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                    title: title.isEmpty ? "Busy" : title,
                    isAllDay: event.isAllDay,
                    startMinutes: minutes(event.startDate),
                    endMinutes: minutes(event.endDate),
                    color: Color(cgColor: event.calendar.cgColor)
                )
            }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startMinutes) < ($1.isAllDay ? 0 : 1, $1.startMinutes) }
    }
}
