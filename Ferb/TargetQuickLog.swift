import Foundation

extension Target {
    /// Whether Quick update (Today's focus) would offer this target right now: it's active,
    /// its current period isn't already met, and it isn't a cap or an NFC target (those are
    /// logged from the Record tab). The evening alert uses the same check, so the two agree.
    func needsQuickLog(asOf now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard isActive(asOf: now, calendar: calendar), let item else { return false }
        if let snoozedUntil, snoozedUntil > now { return false }
        if item.quantityDirection == .cap { return false }
        if item.effectiveMethod == .nfc { return false }
        let current = recentPeriods(1, asOf: now, calendar: calendar).first(where: \.isCurrent)
        return current?.result != .done
    }
}
