import Foundation
import SwiftData

/// Something you act on: "for `durationDays` starting `startDate`, do `item` every
/// `intervalDays` days (aiming for `value` ± `tolerance` on quantity items)."
/// Bumping a target up means adding a new Target row, not editing this one.
@Model
final class Target {
    var item: Item?
    var startDate: Date
    var durationDays: Int?     // nil = ongoing (no end)
    var intervalDays: Int      // cadence: 1 = daily, 7 = weekly, N = every N days
    var value: Double?         // target amount (quantity items); nil for binary items
    var tolerance: Double?     // allowed miss around `value`, read per `toleranceMode`
    var toleranceMode: ToleranceMode = ToleranceMode.absolute
    var reward: String?        // placeholder for later; unused for now
    /// Hidden from lists but kept with its logs. Restore from Settings → Archived.
    var isArchived: Bool = false
    /// Record-tab timer state, saved so a running timer survives leaving the screen or the
    /// app closing. `timerStartedAt` is set while running; `timerAccumulated` is seconds banked
    /// from earlier runs. Both clear when the timer is logged or reset.
    var timerStartedAt: Date?
    var timerAccumulated: Double = 0

    @Relationship(deleteRule: .cascade, inverse: \Log.target)
    var logs: [Log] = []

    init(
        item: Item,
        startDate: Date = .now,
        durationDays: Int? = nil,
        intervalDays: Int = 1,
        value: Double? = nil,
        tolerance: Double? = nil,
        toleranceMode: ToleranceMode = .absolute,
        reward: String? = nil
    ) {
        self.item = item
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.durationDays = durationDays
        self.intervalDays = intervalDays
        self.value = value
        self.tolerance = tolerance
        self.toleranceMode = toleranceMode
        self.reward = reward
    }
}

extension Target {
    /// Derived from the item's subarea — not stored.
    var area: Area? { item?.area }

    var cadenceTitle: String {
        switch intervalDays {
        case 1: "Daily"
        case 7: "Weekly"
        default: "Every \(intervalDays) days"
        }
    }

    var lastCompletedAt: Date? {
        logs.map(\.completedAt).max()
    }

    /// First day the target no longer applies, or nil if ongoing.
    func endDate(calendar: Calendar = .current) -> Date? {
        guard let days = durationDays else { return nil }
        return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: startDate))
    }

    /// Archived on its own, or because its item is archived.
    var isHidden: Bool { isArchived || item?.isArchived == true }

    /// True from the start date through the last day of the window. Archived targets
    /// (or targets of archived items) are never active.
    func isActive(asOf now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !isHidden else { return false }
        let today = calendar.startOfDay(for: now)
        guard today >= calendar.startOfDay(for: startDate) else { return false }
        guard let end = endDate(calendar: calendar) else { return true }
        return today < end
    }
}
