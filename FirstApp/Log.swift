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
