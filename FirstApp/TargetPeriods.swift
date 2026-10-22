import Foundation

enum PeriodResult {
    case done      // goal met
    case missed    // period is over and the goal wasn't met (or a cap was exceeded)
    case open      // current period, not settled yet
    case upcoming  // hasn't started
}

/// One cadence interval inside a target's window. Derived, never stored.
struct TargetPeriod: Identifiable {
    let number: Int          // 1-based
    let start: Date          // first day of the period
    let end: Date            // first day after the period
    let isCurrent: Bool
    let result: PeriodResult
    let loggedValue: Double? // sum for amount/duration, latest for time targets; nil if none

    var id: Int { number }
}

extension Target {
    /// Tolerance converted into the same units as `value`.
    var toleranceAmount: Double {
        guard let tolerance else { return 0 }
        guard toleranceMode == .percent, let value, item?.quantitySubtype != .timeTarget else {
            return tolerance
        }
        return abs(value) * tolerance / 100
    }

    /// "Oct 1 – ongoing" or "Oct 1 – Oct 14".
    var dateRangeText: String {
        let start = startDate.formatted(date: .abbreviated, time: .omitted)
        guard let end = endDate() else { return "\(start) – ongoing" }
        let last = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
        return "\(start) – \(last.formatted(date: .abbreviated, time: .omitted))"
    }

    /// One period per cadence interval: the whole window for a finite target, or from
    /// the start through the current period for an ongoing one.
    func periods(asOf now: Date = .now, calendar: Calendar = .current) -> [TargetPeriod] {
        let layout = layout(asOf: now, calendar: calendar)
        return buildPeriods(layout, indices: 0..<layout.count, calendar: calendar)
    }

    /// The last `limit` periods that have started (the current one and earlier ones).
    /// Much cheaper than `periods()` for a long-running target, so use it wherever only
    /// the latest few periods matter (status, card dots, "is this period done").
    func recentPeriods(_ limit: Int, asOf now: Date = .now, calendar: Calendar = .current) -> [TargetPeriod] {
        let layout = layout(asOf: now, calendar: calendar)
        guard layout.startedCount > 0, limit > 0 else { return [] }
        let lower = max(0, layout.startedCount - limit)
        return buildPeriods(layout, indices: lower..<layout.startedCount, calendar: calendar)
    }

    // MARK: - Building periods

    /// Where the cadence intervals fall. Cheap; the per-period results are the costly part.
    private struct Layout {
        let today: Date
        let first: Date
        let interval: Int
        let windowEnd: Date?
        let count: Int          // periods in the window (or up to the current one if ongoing)
        let startedCount: Int   // how many of them have begun
    }

    private func layout(asOf now: Date, calendar: Calendar) -> Layout {
        let today = calendar.startOfDay(for: now)
        let first = calendar.startOfDay(for: startDate)
        let interval = max(1, intervalDays)
        let elapsed = calendar.dateComponents([.day], from: first, to: today).day ?? 0

        let count: Int
        if let days = durationDays {
            count = days <= 0 ? 0 : (days + interval - 1) / interval
        } else {
            count = max(0, elapsed) / interval + 1
        }
        let startedCount = elapsed < 0 ? 0 : min(count, elapsed / interval + 1)

        return Layout(
            today: today,
            first: first,
            interval: interval,
            windowEnd: endDate(calendar: calendar),
            count: count,
            startedCount: startedCount
        )
    }

    /// Builds the periods at the given indices. Each log's counting date is worked out once
    /// and the logs are sorted, so the periods are filled in a single pass over them
    /// instead of scanning every log for every period.
    private func buildPeriods(_ layout: Layout, indices: Range<Int>, calendar: Calendar) -> [TargetPeriod] {
        guard !indices.isEmpty else { return [] }
        let isCap = item?.quantityDirection == .cap
        let dated = logs
            .map { (date: countingDate(of: $0, calendar: calendar), log: $0) }
            .sorted { $0.date < $1.date }
        var cursor = 0

        return indices.map { index in
            let start = calendar.date(byAdding: .day, value: index * layout.interval, to: layout.first) ?? layout.first
            var end = calendar.date(byAdding: .day, value: layout.interval, to: start) ?? start
            if let windowEnd = layout.windowEnd, end > windowEnd { end = windowEnd }

            // Skip logs before this period, then take the ones inside it.
            while cursor < dated.count && dated[cursor].date < start { cursor += 1 }
            var periodLogs: [Log] = []
            while cursor < dated.count && dated[cursor].date < end {
                periodLogs.append(dated[cursor].log)
                cursor += 1
            }

            let satisfied = isSatisfied(by: periodLogs)
            let isFuture = start > layout.today
            let isCurrent = !isFuture && layout.today < end

            let result: PeriodResult
            if isFuture {
                result = .upcoming
            } else if isCurrent {
                // A cap can still be broken until the period ends; anything else can still be met.
                if isCap { result = satisfied ? .open : .missed } else { result = satisfied ? .done : .open }
            } else {
                result = satisfied ? .done : .missed
            }

            return TargetPeriod(
                number: index + 1,
                start: start,
                end: end,
                isCurrent: isCurrent,
                result: result,
                loggedValue: loggedValue(in: periodLogs)
            )
        }
    }

    /// Evening time goals (noon or later, like a bedtime) count early-morning clock times
    /// toward the night before.
    var isEveningTimeGoal: Bool {
        item?.quantitySubtype == .timeTarget && (value ?? 0) >= 12 * 60
    }

    /// The date a log counts toward. Normally when it was logged; for an evening time goal,
    /// a clock time before noon (12:30 am, say) belongs to the previous day's period.
    func countingDate(of log: Log, calendar: Calendar) -> Date {
        guard isEveningTimeGoal else { return log.completedAt }
        let minutes = log.value ?? {
            let parts = calendar.dateComponents([.hour, .minute], from: log.completedAt)
            return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }()
        guard minutes < 12 * 60 else { return log.completedAt }
        return calendar.date(byAdding: .day, value: -1, to: log.completedAt) ?? log.completedAt
    }

    /// Distance between two clock times in minutes, going the short way around the clock,
    /// so 11:30 pm and 12:30 am are 60 apart, not 1,380.
    private func clockDistance(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 1440)
        return min(diff, 1440 - diff)
    }

    /// Value shown for a period: summed for amount/duration, latest for a time target.
    private func loggedValue(in periodLogs: [Log]) -> Double? {
        let valued = periodLogs.filter { $0.value != nil }
        guard !valued.isEmpty else { return nil }
        if item?.quantitySubtype == .timeTarget {
            return valued.max { $0.completedAt < $1.completedAt }?.value
        }
        return valued.compactMap(\.value).reduce(0, +)
    }

    /// Whether the logs in one period meet the goal, within the tolerance band.
    /// Binary targets are met by any log. Quantity logs without a value (from before values
    /// were recorded) count as met, except that a cap is never broken by them.
    private func isSatisfied(by periodLogs: [Log]) -> Bool {
        guard let goal = value, let item, item.trackingType == .quantity else {
            return !periodLogs.isEmpty
        }
        guard let measured = loggedValue(in: periodLogs) else {
            return item.quantityDirection == .cap ? true : !periodLogs.isEmpty
        }

        let tolerance = toleranceAmount
        if item.quantitySubtype == .timeTarget {
            return clockDistance(measured, goal) <= tolerance
        }
        switch item.quantityDirection {
        case .cap?: return measured <= goal + tolerance
        default: return measured >= goal - tolerance
        }
    }
}
