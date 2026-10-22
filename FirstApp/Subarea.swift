import Foundation
import SwiftData

/// A finer-grained body/habit category. Each subarea belongs to exactly one `Area`.
/// The 34 built-in subareas are seeded on launch (see `Subarea.seedDefaults`);
/// custom ones can be added later. Items point at a subarea.
@Model
final class Subarea {
    /// Stable identifier. Built-ins use the original names (e.g. "hair", "facialHair");
    /// custom subareas get a UUID string. Never change a built-in's key.
    var key: String = ""
    var title: String = ""
    var area: Area = Area.surface
    var isBuiltIn: Bool = false
    /// Position within the app's default ordering; custom subareas sort after built-ins.
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Item.subarea)
    var items: [Item] = []

    init(key: String, title: String, area: Area, isBuiltIn: Bool, sortOrder: Int) {
        self.key = key
        self.title = title
        self.area = area
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
    }
}

extension Subarea {
    /// The built-in subareas, in display order.
    static let defaults: [(key: String, area: Area, title: String)] = [
        // Surface
        ("hair", .surface, "Hair"),
        ("eyes", .surface, "Eyes"),
        ("teeth", .surface, "Teeth"),
        ("face", .surface, "Face"),
        ("facialHair", .surface, "Facial hair"),
        ("upperBodySkin", .surface, "Upper body skin"),
        ("lowerBodySkin", .surface, "Lower body skin"),
        ("bodyHair", .surface, "Body hair"),

        // Structure
        ("posture", .structure, "Posture"),
        ("upperBodyFlexibility", .structure, "Upper body flexibility"),
        ("hipFlexibility", .structure, "Hip flexibility"),
        ("upperLegFlexibility", .structure, "Upper leg flexibility"),
        ("lowerLegFlexibility", .structure, "Lower leg flexibility"),
        ("backMuscles", .structure, "Back muscles"),
        ("biceps", .structure, "Biceps"),
        ("triceps", .structure, "Triceps"),
        ("chest", .structure, "Chest"),
        ("coreMuscles", .structure, "Core muscles"),
        ("quads", .structure, "Quads"),
        ("hamstrings", .structure, "Hamstrings"),
        ("calves", .structure, "Calves"),
        ("glutes", .structure, "Glutes"),
        ("handWristMobility", .structure, "Hand & wrist mobility"),
        ("footAnkleMobility", .structure, "Foot & ankle mobility"),

        // Internal
        ("cardiovascular", .internals, "Cardiovascular"),
        ("pulmonary", .internals, "Pulmonary"),
        ("hydration", .internals, "Hydration"),
        ("digestive", .internals, "Digestive"),
        ("fat", .internals, "Fat"),
        ("immunity", .internals, "Immunity"),

        // Regulation
        ("sleep", .regulation, "Sleep"),
        ("brain", .regulation, "Brain"),
        ("rewardSystem", .regulation, "Reward system"),
        ("spirit", .regulation, "Spirit")
    ]

    /// Inserts any built-in subarea that isn't in the store yet. Safe to call on every
    /// launch: existing rows are left alone, so edits and attached items are untouched.
    static func seedDefaults(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Subarea>())) ?? []
        let existingKeys = Set(existing.map(\.key))
        for (index, entry) in defaults.enumerated() where !existingKeys.contains(entry.key) {
            context.insert(Subarea(
                key: entry.key,
                title: entry.title,
                area: entry.area,
                isBuiltIn: true,
                sortOrder: index
            ))
        }
        try? context.save()
    }
}
