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

extension Optional where Wrapped == TargetStatus {
    var color: Color {
        switch self {
        case nil: .gray
        case .done?: .green
        case .due?: .yellow
        case .overdue?: .red
        }
    }
}
