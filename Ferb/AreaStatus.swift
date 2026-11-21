import SwiftUI

extension Collection where Element == Target {
    /// Targets in effect today whose item lives in the given area.
    func active(in area: Area, asOf now: Date = .now) -> [Target] {
        filter { $0.area == area && $0.isActive(asOf: now) }
    }

    /// Status for the whole area, or nil if there are no targets. Green when everything is
    /// met, yellow when anything is still open. Never red: a broken cap is a today-only fact,
    /// and one target shouldn't paint the whole area.
    var overallStatus: TargetStatus? {
        guard !isEmpty else { return nil }
        return map { $0.status() }.contains { $0 != .done } ? .due : .done
    }
}

extension Color {
    /// The one dark green that means "goal met" everywhere in the app (Home's dark green tile,
    /// status tints, dots, calendar). Change it here to change them all.
    static let goalMet = Color(red: 0.05, green: 0.52, blue: 0.22)

    /// The matching dark red for a miss (skipped period, broken cap, time target outside its window).
    static let goalMissed = Color(red: 0.80, green: 0.04, blue: 0.07)

    /// The blue for "set aside" / Later. Home's blue tile, the card tints and the Quick update
    /// buttons all read it, so changing it here changes them all.
    static let setAside = Color.blue
}

extension Optional where Wrapped == TargetStatus {
    var color: Color {
        switch self {
        case nil: .gray
        case .done?: .goalMet
        case .due?: .yellow
        case .overdue?: .goalMissed
        }
    }
}
