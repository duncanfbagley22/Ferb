import SwiftUI
import Charts

/// Streaks and completion for one target, derived from its periods. Nothing is stored.
/// A missed period (or a broken cap) ends a streak. The current period, while it is still
/// open, neither extends nor ends one, and periods that haven't started are ignored.
struct TargetStats {
    let doneCount: Int
    let missedCount: Int
    let currentStreak: Int
    let longestStreak: Int

    var settledCount: Int { doneCount + missedCount }

    /// Done periods over done + missed ones. Nil until a period has been settled.
    var completionRate: Double? {
        settledCount > 0 ? Double(doneCount) / Double(settledCount) : nil
    }

    init(periods: [TargetPeriod]) {
        var done = 0
        var missed = 0
        var run = 0
        var longest = 0
        for period in periods {
            switch period.result {
            case .done:
                done += 1
                run += 1
                longest = max(longest, run)
            case .missed:
                missed += 1
                run = 0
            case .open, .upcoming:
                break
            }
        }
        doneCount = done
        missedCount = missed
        currentStreak = run
        longestStreak = longest
    }
}

extension Target {
    func stats(asOf now: Date = .now, calendar: Calendar = .current) -> TargetStats {
        TargetStats(periods: periods(asOf: now, calendar: calendar))
    }

    /// "1 day", "12 days", "3 weeks", "4 periods": streaks count cadence intervals.
    func streakText(_ count: Int) -> String {
        let singular: String
        let plural: String
        switch intervalDays {
        case 1: (singular, plural) = ("day", "days")
        case 7: (singular, plural) = ("week", "weeks")
        default: (singular, plural) = ("period", "periods")
        }
        return "\(count) \(count == 1 ? singular : plural)"
    }
}

/// A streak and the target it belongs to (for the History cards).
struct StreakLeader {
    let target: Target
    let streak: Int

    var text: String { target.streakText(streak) }
    var name: String { target.item?.name ?? "Target" }
}

extension Collection where Element == Target {
    /// The longest running streak among targets in effect today. Nil when none is above 0.
    func bestCurrentStreak(asOf now: Date = .now) -> StreakLeader? {
        var best: StreakLeader?
        for target in self where target.isActive(asOf: now) {
            let streak = target.stats(asOf: now).currentStreak
            if streak > (best?.streak ?? 0) {
                best = StreakLeader(target: target, streak: streak)
            }
        }
        return best
    }

    /// The longest streak any of these targets has ever had. Nil when none is above 0.
    func bestLongestStreak(asOf now: Date = .now) -> StreakLeader? {
        var best: StreakLeader?
        for target in self {
            let streak = target.stats(asOf: now).longestStreak
            if streak > (best?.streak ?? 0) {
                best = StreakLeader(target: target, streak: streak)
            }
        }
        return best
    }

    /// Periods settled as done during the current calendar week, across these targets.
    /// Only the last 8 started periods of each are looked at, enough for a daily target.
    func doneThisWeek(asOf now: Date = .now, calendar: Calendar = .current) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return reduce(0) { total, target in
            let hits = target.recentPeriods(8, asOf: now, calendar: calendar).filter { period in
                guard period.result == .done, let settled = period.settledOn else { return false }
                return week.contains(settled)
            }
            return total + hits.count
        }
    }
}

/// The block pinned under the period list on the target page: streak, best streak and
/// completion, plus (for amount and duration targets) a bar per recent period against the
/// goal line. Binary and time targets get the numbers only.
struct TargetStatsBlock: View {
    let target: Target
    let periods: [TargetPeriod]

    private static let barCount = 14

    private var stats: TargetStats { TargetStats(periods: periods) }

    private var barPeriods: [TargetPeriod] {
        Array(periods.filter { $0.result != .upcoming }.suffix(Self.barCount))
    }

    private var showsChart: Bool {
        guard let item = target.item, item.trackingType == .quantity,
              item.quantitySubtype != .timeTarget, target.value != nil else { return false }
        return !barPeriods.isEmpty
    }

    private var completionText: String {
        guard let rate = stats.completionRate else { return "—" }
        return rate.formatted(.percent.precision(.fractionLength(0)))
    }

    private func color(for result: PeriodResult) -> Color {
        switch result {
        case .done: .green
        case .missed: .red
        case .open, .upcoming: .gray
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                stat(target.streakText(stats.currentStreak), "Streak")
                stat(target.streakText(stats.longestStreak), "Best streak")
                stat(completionText, "Completion")
            }

            if showsChart {
                Chart {
                    ForEach(barPeriods) { period in
                        BarMark(
                            x: .value("Period", String(period.number)),
                            y: .value("Logged", period.loggedValue ?? 0)
                        )
                        .foregroundStyle(color(for: period.result))
                    }
                    if let goal = target.value {
                        RuleMark(y: .value("Goal", goal))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                }
                .frame(height: 70)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
