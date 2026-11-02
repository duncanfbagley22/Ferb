import Foundation
import SwiftData
import UserNotifications
import UIKit
import Observation

/// What the last notification rebuild did about iOS's limit of 64 pending notifications, so
/// screens can warn about it instead of plan alerts quietly going missing.
@Observable
final class AlertCapacity {
    static let shared = AlertCapacity()

    /// Notifications that were scheduled (all kinds).
    var scheduled = 0
    /// Plan alerts wanted in the window but left out to stay under the limit.
    var droppedPlan = 0
    /// Requests iOS refused when they were added.
    var failed = 0

    /// Close to the budget, though nothing has been left out yet.
    var isNearLimit: Bool { scheduled >= ReminderScheduler.nearLimit }
    /// Something that should have been scheduled wasn't (or the other alerts alone are over).
    var hasProblem: Bool { droppedPlan > 0 || failed > 0 || scheduled > ReminderScheduler.systemLimit }
}

/// Turns the saved `Reminder` settings into real notifications.
///
/// It works by clearing every notification this app has scheduled and re-adding them from
/// the saved settings, so call `refresh` any time they (or what's left to log) might have
/// changed.
///
/// - Morning and custom reminders are one repeating request per enabled weekday.
/// - The evening reminder is a rolling window of one-off requests for the next few days.
///   That lets it skip tonight when nothing is left to log, which a repeating request
///   can't do. The window is rebuilt whenever the app opens or something changes, so it only
///   runs out if the app goes unopened for `alertWindowDays` days.
enum ReminderScheduler {
    /// Every request this scheduler makes starts with this, so it never touches anything else.
    private static let idPrefix = "reminder."
    private static let eveningPrefix = "reminder.evening."

    /// How many days ahead the rolling alerts (the evening one now, plan slots later) are
    /// scheduled. They're rebuilt whenever the app opens, so they only run out after this many
    /// unopened days.
    private static let alertWindowDays = 5

    /// UserDefaults key for the Settings → Alerts "Plan alerts" switch (off until turned on).
    static let planAlertsKey = "planAlertsEnabled"
    /// iOS keeps at most this many pending notifications per app.
    static let systemLimit = 64
    /// What this scheduler stays within, leaving a little spare under `systemLimit`.
    static let pendingBudget = 60
    /// `AlertCapacity.isNearLimit` turns on at this many scheduled notifications.
    static let nearLimit = 50
    private static let planPrefix = "reminder.plan."

    /// Bumped on every refresh so an older, slower refresh can stop once a newer one starts.
    private static var generation = 0

    /// Where to send someone who has denied notifications.
    static var settingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    /// Start-of-day and end-of-day alerts open Quick update when tapped. Custom ones just open the app.
    static func opensQuickUpdate(identifier: String) -> Bool {
        identifier.hasPrefix("reminder.morning.") || identifier.hasPrefix(eveningPrefix)
    }

    /// Whether the app is allowed to send notifications right now.
    static func currentStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Rebuilds the scheduled notifications from the saved reminders.
    /// With `requestingPermission`, asks iOS for permission first if it hasn't been asked
    /// yet, but only when at least one reminder is on.
    @discardableResult
    static func refresh(in context: ModelContext, requestingPermission: Bool) async -> UNAuthorizationStatus {
        generation += 1
        let myGeneration = generation
        let center = UNUserNotificationCenter.current()

        let enabled = ((try? context.fetch(FetchDescriptor<Reminder>())) ?? [])
            .filter(\.isEnabled)

        let planOn = UserDefaults.standard.bool(forKey: planAlertsKey)
        let planEntries = planOn ? ((try? context.fetch(FetchDescriptor<PlanEntry>())) ?? []) : []

        // What the evening alert depends on: the same check Quick update uses.
        let targets = (try? context.fetch(FetchDescriptor<Target>())) ?? []
        let hasActiveTargets = targets.contains { $0.isActive() }
        let leftToLog = targets.contains { $0.needsQuickLog() }

        var status = await currentStatus()
        if status == .notDetermined, requestingPermission, !enabled.isEmpty || planOn {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await currentStatus()
        }

        // Clear what we scheduled before.
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard status == .authorized || status == .provisional || status == .ephemeral else {
            let capacity = AlertCapacity.shared
            capacity.scheduled = 0
            capacity.droppedPlan = 0
            capacity.failed = 0
            return status
        }

        // Nothing left to log: take down an end-of-day notification that already arrived.
        if !leftToLog {
            let delivered = await center.deliveredNotifications()
            let stale = delivered.map(\.request.identifier).filter { $0.hasPrefix(eveningPrefix) }
            center.removeDeliveredNotifications(withIdentifiers: stale)
        }

        let baseRequests = enabled.flatMap {
            requests(for: $0, hasActiveTargets: hasActiveTargets, leftToLog: leftToLog)
        }
        // Plan alerts go last, soonest first. Whatever doesn't fit under the budget is counted
        // (not silently lost) so the screens can warn about it.
        let planCandidates = planOn ? planRequests(for: planEntries) : []
        let room = max(0, pendingBudget - baseRequests.count)
        let keptPlan = planCandidates.prefix(room).map { $0.request }
        let allRequests = baseRequests + keptPlan

        var failed = 0
        for request in allRequests {
            // A newer refresh has started with fresher settings; let it finish the job.
            guard myGeneration == generation else { return status }
            do {
                try await center.add(request)
            } catch {
                failed += 1
            }
        }

        let capacity = AlertCapacity.shared
        capacity.scheduled = allRequests.count - failed
        capacity.droppedPlan = planCandidates.count - keptPlan.count
        capacity.failed = failed
        return status
    }

    // MARK: - Building requests

    private static func requests(
        for reminder: Reminder,
        hasActiveTargets: Bool,
        leftToLog: Bool
    ) -> [UNNotificationRequest] {
        switch reminder.kind {
        case .morning, .custom:
            return reminder.weekdays.map { weeklyRequest(for: reminder, weekday: $0) }
        case .evening:
            return eveningRequests(for: reminder, hasActiveTargets: hasActiveTargets, leftToLog: leftToLog)
        }
    }

    /// One-off requests for each enabled day in the window. Today's is only added if there's
    /// still something to log and the time hasn't passed. Later days can't be known yet, so
    /// they're added as long as there are active targets, and re-checked on the next refresh.
    private static func eveningRequests(
        for reminder: Reminder,
        hasActiveTargets: Bool,
        leftToLog: Bool
    ) -> [UNNotificationRequest] {
        guard hasActiveTargets else { return [] }

        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let content = content(for: reminder)
        var requests: [UNNotificationRequest] = []

        for offset in 0..<alertWindowDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  reminder.weekdays.contains(calendar.component(.weekday, from: day)) else { continue }

            var when = calendar.dateComponents([.year, .month, .day], from: day)
            when.hour = reminder.hour
            when.minute = reminder.minute
            guard let fireDate = calendar.date(from: when), fireDate > now else { continue }
            if offset == 0 && !leftToLog { continue }

            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            let identifier = "\(identifierBase(for: reminder)).\(when.year ?? 0)-\(when.month ?? 0)-\(when.day ?? 0)"
            requests.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
        return requests
    }

    /// One request per planned slot per day in the window, soonest first. A slot alerts only
    /// if its item still needs logging: checked exactly for today, and for later days (which
    /// can't be known yet) only that the item has an active target Quick update could offer.
    /// Later days are re-checked on every rebuild.
    private static func planRequests(for entries: [PlanEntry]) -> [(date: Date, request: UNNotificationRequest)] {
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        var result: [(date: Date, request: UNNotificationRequest)] = []

        for offset in 0..<alertWindowDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)

            for entry in entries {
                guard let item = entry.item, !item.isArchived else { continue }
                if let date = entry.date {
                    guard calendar.isDate(date, inSameDayAs: day) else { continue }
                } else if entry.weekday != weekday {
                    continue
                }

                var when = calendar.dateComponents([.year, .month, .day], from: day)
                when.hour = entry.startMinutes / 60
                when.minute = entry.startMinutes % 60
                guard let fireDate = calendar.date(from: when), fireDate > now else { continue }

                let needsLogging: Bool
                if offset == 0 {
                    needsLogging = item.targets.contains { $0.needsQuickLog() }
                } else {
                    needsLogging = item.quantityDirection != .cap && item.effectiveMethod != .nfc
                        && item.targets.contains { $0.isActive(asOf: fireDate) }
                }
                guard needsLogging else { continue }

                let content = UNMutableNotificationContent()
                content.title = item.name
                content.body = "Planned for now (\(lengthText(minutes: entry.durationMinutes)))."
                content.sound = .default

                let stamp = Int(entry.createdAt.timeIntervalSince1970 * 1000)
                let identifier = "\(planPrefix)\(stamp).\(entry.weekday).\(entry.startMinutes).\(when.year ?? 0)-\(when.month ?? 0)-\(when.day ?? 0)"
                let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
                result.append((
                    date: fireDate,
                    request: UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                ))
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    private static func lengthText(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    private static func weeklyRequest(for reminder: Reminder, weekday: Int) -> UNNotificationRequest {
        var when = DateComponents()
        when.hour = reminder.hour
        when.minute = reminder.minute
        when.weekday = weekday
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        return UNNotificationRequest(
            identifier: "\(identifierBase(for: reminder)).\(weekday)",
            content: content(for: reminder),
            trigger: trigger
        )
    }

    private static func content(for reminder: Reminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        switch reminder.kind {
        case .morning:
            content.title = "Today's focus"
            content.body = "Open the app to see what's on today."
        case .evening:
            content.title = "End of day"
            content.body = "Anything left to track today?"
        case .custom:
            content.title = reminder.displayTitle
        }
        content.sound = .default
        return content
    }

    /// Stable per reminder, so a rebuild reuses the same ids. The evening one starts with
    /// `eveningPrefix` so delivered end-of-day notifications can be found and cleared.
    private static func identifierBase(for reminder: Reminder) -> String {
        let stamp = Int(reminder.createdAt.timeIntervalSince1970 * 1000)
        return "\(idPrefix)\(reminder.kind.rawValue).\(stamp)"
    }
}
