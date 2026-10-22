import Foundation
import SwiftData

/// A thing that can be targeted against. Items are definitions — you don't act on
/// them directly; you act on their `Target`s.
@Model
final class Item {
    var name: String
    var subarea: Subarea?
    var createdAt: Date
    var trackingType: TrackingType = TrackingType.binary
    var binarySubtype: BinarySubtype? = BinarySubtype.didIt
    var quantitySubtype: QuantitySubtype? = nil
    var quantityDirection: QuantityDirection? = nil
    var unit: QuantityUnit? = nil
    var isPriority: Bool = false
    /// Hidden from lists but kept (with its targets and logs). Restore from Settings → Archived.
    var isArchived: Bool = false
    /// How it's logged on the Record tab. Nil means "derive it from the tracking type",
    /// so items created before this field existed keep working.
    var method: TrackingMethod? = nil

    @Relationship(deleteRule: .cascade, inverse: \Target.item)
    var targets: [Target] = []

    init(
        name: String,
        subarea: Subarea,
        createdAt: Date = .now,
        trackingType: TrackingType = .binary,
        binarySubtype: BinarySubtype? = .didIt,
        quantitySubtype: QuantitySubtype? = nil,
        quantityDirection: QuantityDirection? = nil,
        unit: QuantityUnit? = nil,
        isPriority: Bool = false,
        method: TrackingMethod? = nil
    ) {
        self.name = name
        self.subarea = subarea
        self.createdAt = createdAt
        self.trackingType = trackingType
        self.binarySubtype = binarySubtype
        self.quantitySubtype = quantitySubtype
        self.quantityDirection = quantityDirection
        self.unit = unit
        self.isPriority = isPriority
        self.method = method
    }
}

extension Item {
    /// Derived from the item's subarea — not stored. Nil only if its subarea was deleted.
    var area: Area? { subarea?.area }

    /// The stored method, or a sensible default for items that don't have one yet.
    var effectiveMethod: TrackingMethod {
        if let method { return method }
        guard trackingType == .quantity else { return .check }
        return quantitySubtype == .duration ? .timer : .number
    }
}
