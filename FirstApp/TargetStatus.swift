import Foundation

enum TargetStatus {
    case done      // nothing needed right now
    case due       // still needs doing this period
    case overdue   // the previous period was missed, or a cap was already broken

    var title: String {
        switch self {
        case .done: "Done"
        case .due: "Due"
        case .overdue: "Overdue"
        }
    }
}

extension Target {
    /// Read from the same period results the detail screen and Calendar use, so every
    /// tint in the app agrees with what's inside the target.
    ///
    /// - Done: the current period is met, or it's a cap that hasn't been broken.
    /// - Due: the current period is still open and the one before it wasn't missed.
    /// - Overdue: the current period is open but the previous one was missed, or a cap
    ///   was already broken this period.
    func status(asOf now: Date = .now, calendar: Calendar = .current) -> TargetStatus {
        let list = recentPeriods(2, asOf: now, calendar: calendar)
        guard let current = list.first(where: \.isCurrent) else { return .done }

        switch current.result {
        case .done, .upcoming:
            return .done
        case .missed:
            // Only a cap can be missed while its period is still running.
            return .overdue
        case .open:
            if item?.quantityDirection == .cap { return .done }
            let previous = list.first { $0.number == current.number - 1 }
            return previous?.result == .missed ? .overdue : .due
        }
    }
}
