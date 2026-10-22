import SwiftUI
import SwiftData

/// Compact card for the area screen's 3-across grid: name, short details, and a row of
/// dots for the most recent periods. The card is tinted by the target's status.
struct TargetGridCard: View {
    let target: Target

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
            text = "\(Target.formatted(value)) \(item.unit?.title.lowercased() ?? "")"
                .trimmingCharacters(in: .whitespaces)
        case .duration:
            text = "\(Target.formatted(value)) min"
        case .timeTarget:
            text = Target.clock(minutes: Int(value))
        }
        return subtype.supportsDirection && item.quantityDirection == .cap ? "≤ \(text)" : text
    }

    private var recentPeriods: [TargetPeriod] {
        target.recentPeriods(dotCount)
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

            HStack(spacing: 4) {
                ForEach(recentPeriods) { period in
                    dot(for: period.result)
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
    /// e.g. "Target · 10,000 steps ± 500" or "Cap · 60 min". Nil for binary items.
    var valueSummary: String? {
        guard let value, let item, item.trackingType == .quantity,
              let subtype = item.quantitySubtype else { return nil }

        var text: String
        switch subtype {
        case .amount:
            text = "\(Self.formatted(value)) \(item.unit?.title.lowercased() ?? "")"
        case .duration:
            text = "\(Self.formatted(value)) min"
        case .timeTarget:
            text = Self.clock(minutes: Int(value))
        }
        if let tolerance {
            if toleranceMode == .percent && subtype != .timeTarget {
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
