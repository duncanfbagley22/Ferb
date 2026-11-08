import SwiftUI
import SwiftData

/// Compact card for the area screen's 3-across grid: name, short details, and a row of
/// dots for the most recent periods. The card is tinted by the target's status.
struct TargetGridCard: View {
    let target: Target
    /// For a count target: show the usual history row instead of this period's time dots.
    var showHistory = false

    private let dotCount = 6

    private var statusColor: Color {
        let status: TargetStatus? = target.status()
        return status.color
    }

    private var cadenceText: String {
        switch target.intervalDays {
        case 1: "Daily"
        case 7: "Weekly"
        default: "Every \(target.intervalDays)d"
        }
    }

    /// Short value for the card, e.g. "10,000 steps" or "≤ 60 min". Tolerance is left to the detail screen.
    private var valueText: String? {
        guard let value = target.value, let item = target.item,
              item.trackingType == .quantity, let subtype = item.quantitySubtype else { return nil }
        let text: String
        switch subtype {
        case .amount:
            text = "\(Target.formatted(value)) \(item.unitName)"
                .trimmingCharacters(in: .whitespaces)
        case .duration:
            text = "\(Target.formatted(value)) min"
        case .timeTarget:
            let clock = Target.clock(minutes: Int(value))
            switch target.timeDirection {
            case .either: text = clock
            case .noLaterThan: text = "by \(clock)"
            case .noEarlierThan: text = "after \(clock)"
            }
        }
        return subtype.supportsDirection && item.quantityDirection == .cap ? "≤ \(text)" : text
    }

    private var recentPeriods: [TargetPeriod] {
        target.recentPeriods(dotCount)
    }

    /// For a "3 times a week" target: how many of the current period's times are done, and the total.
    private var timesProgress: (done: Int, total: Int)? {
        guard let total = target.timesGoal,
              let current = recentPeriods.last(where: \.isCurrent) else { return nil }
        let logged = Int((current.loggedValue ?? 0).rounded(.down))
        let done = current.result == .done ? total : min(total, max(0, logged))
        return (done, total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(target.item?.name ?? "Unknown item")
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(cadenceText)
                if let valueText {
                    Text(valueText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if let progress = timesProgress, !showHistory {
                // "3 times a week": one dot per time, filled as each is done this period. These are
                // the card's only dots, in place of the history row.
                HStack(spacing: 4) {
                    ForEach(0..<progress.total, id: \.self) { index in
                        if index < progress.done {
                            Circle().fill(.green).frame(width: 8, height: 8)
                        } else {
                            Circle().strokeBorder(.secondary, lineWidth: 1).frame(width: 8, height: 8)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(progress.done) of \(progress.total) times this period")
            } else {
                HStack(spacing: 4) {
                    ForEach(recentPeriods) { period in
                        dot(for: period.result)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(statusColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Green = met, red = missed, hollow = still open.
    @ViewBuilder
    private func dot(for result: PeriodResult) -> some View {
        switch result {
        case .done:
            Circle().fill(.green).frame(width: 8, height: 8)
        case .missed:
            Circle().fill(.red).frame(width: 8, height: 8)
        default:
            Circle().strokeBorder(.secondary, lineWidth: 1).frame(width: 8, height: 8)
        }
    }
}

extension Target {
    /// The number of times in a "3 times a week" style goal, or nil for any other target: an amount in
    /// Times (not a cap) with a whole goal of 2 to 6, since more dots than that are too small to read.
    var timesGoal: Int? {
        guard let item, item.trackingType == .quantity,
              item.quantitySubtype == .amount,
              item.quantityDirection != .cap,
              item.unit == .times,
              item.customUnit == nil,
              let goal = value, goal >= 2, goal <= 6, goal == goal.rounded()
        else { return nil }
        return Int(goal)
    }

    /// e.g. "Target · 10,000 steps ± 500" or "Cap · 60 min". Nil for binary items.
    var valueSummary: String? {
        guard let value, let item, item.trackingType == .quantity,
              let subtype = item.quantitySubtype else { return nil }

        var text: String
        switch subtype {
        case .amount:
            text = "\(Self.formatted(value)) \(item.unitName)"
        case .duration:
            text = "\(Self.formatted(value)) min"
        case .timeTarget:
            let clock = Self.clock(minutes: Int(value))
            text = timeDirection == .either ? clock : "\(timeDirection.title) \(clock)"
        }
        if let tolerance {
            if subtype == .timeTarget, timeDirection != .either {
                let sign = timeDirection == .noLaterThan ? "+" : "−"
                text += " (\(sign)\(Self.formatted(tolerance)) min)"
            } else if toleranceMode == .percent && subtype != .timeTarget {
                text += " ± \(Self.formatted(tolerance))%"
            } else {
                text += " ± \(Self.formatted(tolerance))"
                if subtype != .amount { text += " min" }
            }
        }
        if subtype.supportsDirection, let direction = item.quantityDirection {
            text = "\(direction.title) · \(text)"
        }
        return text
    }

    static func formatted(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func clock(minutes: Int) -> String {
        let parts = DateComponents(hour: (minutes / 60) % 24, minute: minutes % 60)
        let date = Calendar.current.date(from: parts) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
