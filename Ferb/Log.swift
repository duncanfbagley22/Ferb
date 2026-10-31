import Foundation
import SwiftData

@Model
final class Log {
    var target: Target?
    var completedAt: Date
    var value: Double?   // optional number for targets you measure, like minutes

    init(target: Target, completedAt: Date = .now, value: Double? = nil) {
        self.target = target
        self.completedAt = completedAt
        self.value = value
    }
}

extension Target {
    /// Creates a log, attaches it to this target's list right away, and saves. Adding it to
    /// `logs` ourselves means every screen that works out colors from that list redraws at
    /// once instead of waiting for SwiftData to fix up the relationship a moment later.
    @discardableResult
    func record(value: Double? = nil, at date: Date = .now, in context: ModelContext) -> Log {
        let log = Log(target: self, completedAt: date, value: value)
        context.insert(log)
        if !logs.contains(where: { $0 === log }) { logs.append(log) }
        try? context.save()
        return log
    }

    /// Deletes a log, removing it from this target's list right away.
    func remove(_ log: Log, in context: ModelContext) {
        logs.removeAll { $0 === log }
        context.delete(log)
        try? context.save()
    }
}
