import Foundation
import SwiftData

/// Which kind of alert a `Reminder` is. There is exactly one morning and one evening
/// reminder (seeded on launch); custom ones are whatever you add.
enum ReminderKind: String, Codable, CaseIterable {
    case morning, evening, custom
}

/// A notification setting: when it should go off and whether it's on.
/// This only stores the settings. Scheduling the actual notifications comes later.
@Model
final class Reminder {
    var kind: ReminderKind = ReminderKind.custom
    /// Only used by custom reminders; the built-in ones have fixed titles.
    var label: String = ""
    var hour: Int = 9
    var minute: Int = 0
    /// Calendar weekday numbers the reminder repeats on (1 = Sunday ... 7 = Saturday).
    var weekdays: [Int] = [1, 2, 3, 4, 5, 6, 7]
    var isEnabled: Bool = false
    var createdAt: Date = Date.now

    init(
        kind: ReminderKind,
        label: String = "",
        hour: Int,
        minute: Int = 0,
        weekdays: [Int] = [1, 2, 3, 4, 5, 6, 7],
        isEnabled: Bool = false,
        createdAt: Date = .now
    ) {
        self.kind = kind
        self.label = label
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

extension Reminder {
    var displayTitle: String {
        switch kind {
        case .morning:
            return "Start of day"
        case .evening:
            return "End of day"
        case .custom:
            let trimmed = label.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "Reminder" : trimmed
        }
    }

    /// The time of day as a Date (today's date, this reminder's hour and minute).
    var timeOfDay: Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }

    var timeText: String {
        timeOfDay.formatted(date: .omitted, time: .shortened)
    }

    var daysText: String {
        let days = Set(weekdays)
        if days.count == 7 { return "Every day" }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        if days.isEmpty { return "Never" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
    }

    var summary: String {
        "\(timeText) · \(daysText)"
    }

    /// Inserts the morning and evening reminders if they aren't in the store yet.
    /// Safe to call on every launch: existing rows (and your edits) are left alone.
    /// They start off, so nothing fires until you turn them on.
    static func seedDefaults(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        let kinds = Set(existing.map(\.kind))
        if !kinds.contains(.morning) {
            context.insert(Reminder(kind: .morning, hour: 8))
        }
        if !kinds.contains(.evening) {
            context.insert(Reminder(kind: .evening, hour: 20))
        }
        try? context.save()
    }
}
