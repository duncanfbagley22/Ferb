import Foundation
import SwiftData

/// A unit you added yourself (pushups, glasses...), offered next to the built-in
/// `QuantityUnit`s when you set up an amount item. Items point at one through
/// `Item.customUnit`; a built-in unit is stored in `Item.unit` instead, never both.
@Model
final class CustomUnit {
    var name: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Item.customUnit)
    var items: [Item] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}
