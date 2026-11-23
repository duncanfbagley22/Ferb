import Foundation

extension Target {
    /// Whether Quick update (Today's focus) would offer this target right now: it's active,
    /// its current period isn't already met, and it isn't a cap or an NFC target (those are
    /// logged from the Record tab). The evening alert uses the same check, so the two agree.
    func needsQuickLog(asOf now: Date = .now, calendar: Calendar = .current, ignoringShowTime: Bool = false) -> Bool {
        guard isActive(asOf: now, calendar: calendar), let item else { return false }
        if let snoozedUntil, snoozedUntil > now { return false }
        if !ignoringShowTime, isBeforeShowTime(asOf: now, calendar: calendar) { return false }
        if item.quantityDirection == .cap { return false }
        if item.effectiveMethod == .nfc { return false }
        let current = recentPeriods(1, asOf: now, calendar: calendar).first(where: \.isCurrent)
        // A non-cap period can only be missed while still running if it was skipped with X.
        if current?.result == .missed { return false }
        // A time target gets one try per period: once a time is logged (even outside its
        // window), it isn't offered again.
        if item.quantitySubtype == .timeTarget, current?.loggedValue != nil { return false }
        return current?.result != .done
    }

    /// True while the clock is before this target's daily "show from" time. Nil time = never.
    func isBeforeShowTime(asOf now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let showFromMinutes else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minutes < showFromMinutes
    }

    /// Whether Quick update (not the alerts) offers this target. Same as `needsQuickLog`, except
    /// caps are included: a cap is offered once a day, until something is logged for it today
    /// (or it's set aside with Not today). Caps stay out of `needsQuickLog` on purpose, so the
    /// evening alert doesn't fire for a cap that stays open all day.
    func needsQuickUpdate(asOf now: Date = .now, calendar: Calendar = .current, ignoringShowTime: Bool = false) -> Bool {
        guard let item, item.quantityDirection == .cap else {
            return needsQuickLog(asOf: now, calendar: calendar, ignoringShowTime: ignoringShowTime)
        }
        guard isActive(asOf: now, calendar: calendar) else { return false }
        if let snoozedUntil, snoozedUntil > now { return false }
        if !ignoringShowTime, isBeforeShowTime(asOf: now, calendar: calendar) { return false }
        if item.effectiveMethod == .nfc { return false }
        return !logs.contains { calendar.isDate($0.completedAt, inSameDayAs: now) }
    }

    /// Whether this target counts toward the red badge on the app icon: flagged "Badge until done"
    /// and still needing a log. Same rules as Quick update (logging, Skip and Not today clear it),
    /// except the show-from time is ignored, so the badge is there from the start of the day.
    func needsBadge(asOf now: Date = .now, calendar: Calendar = .current) -> Bool {
        badgeNudge == true && needsQuickUpdate(asOf: now, calendar: calendar, ignoringShowTime: true)
    }
}
