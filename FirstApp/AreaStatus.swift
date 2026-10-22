import SwiftUI

extension Collection where Element == Target {
    /// Targets in effect today whose item lives in the given area.
    func active(in area: Area, asOf now: Date = .now) -> [Target] {
        filter { $0.area == area && $0.isActive(asOf: now) }
    }

    /// Worst status among the targets, or nil if there are none.
    var overallStatus: TargetStatus? {
        guard !isEmpty else { return nil }
        let statuses = map { $0.status() }
        if statuses.contains(.overdue) { return .overdue }
        if statuses.contains(.due) { return .due }
        return .done
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
