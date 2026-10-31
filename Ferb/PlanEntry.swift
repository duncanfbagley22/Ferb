import Foundation
import SwiftData

/// One slot in the weekly morning-plan template, or a one-off slot on a single day: an item, at an
/// exact time for some number of minutes. With no `date` it repeats every week on `weekday`; with a
/// `date` it appears only on that day. It points at the item (not a target) so it keeps working
/// when the item's target is replaced.
@Model
final class PlanEntry {
    /// Calendar weekday number (1 = Sunday ... 7 = Saturday).
    var weekday: Int = 2
    /// Start time as minutes since midnight.
    var startMinutes: Int = 420
    var durationMinutes: Int = 15
    var item: Item?
    var createdAt: Date = Date.now
    /// nil = repeats every week on `weekday`. Set (start of that day) = a one-off slot on just
    /// that date; `weekday` is then that date's weekday. Optional so slots saved before this
    /// field existed read as weekly.
    var date: Date?

    init(item: Item?, weekday: Int, startMinutes: Int, durationMinutes: Int, createdAt: Date = .now, date: Date? = nil) {
        self.item = item
        self.weekday = weekday
        self.startMinutes = startMinutes
        self.durationMinutes = durationMinutes
        self.createdAt = createdAt
        self.date = date
    }

    /// Minutes since midnight at which the slot ends (capped at the end of the day).
    var endMinutes: Int { min(startMinutes + durationMinutes, 24 * 60) }
}

extension Item {
    /// A sensible slot length in minutes: the current duration goal if the item has one,
    /// rounded to 5 minutes, otherwise 15.
    var defaultPlanMinutes: Int {
        guard trackingType == .quantity, quantitySubtype == .duration,
              let goal = targets.filter({ $0.isActive() }).max(by: { $0.startDate < $1.startDate })?.value,
              goal > 0 else { return 15 }
        let rounded = Int((goal / 5).rounded()) * 5
        return min(max(rounded, 5), 240)
    }
}
