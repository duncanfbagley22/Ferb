import Foundation

enum TrackingType: String, Codable, CaseIterable {
    case binary
    case quantity
}

enum BinarySubtype: String, Codable, CaseIterable, Identifiable {
    case didIt
    case avoidedIt
    case stateCheck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .didIt: "Did it"
        case .avoidedIt: "Avoided it"
        case .stateCheck: "State check"
        }
    }
}

enum QuantitySubtype: String, Codable, CaseIterable, Identifiable {
    case amount
    case duration
    case timeTarget

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amount: "Amount"
        case .duration: "Duration"
        case .timeTarget: "Time target"
        }
    }

    /// Cap/target direction only applies to amount and duration, not a clock-time target.
    var supportsDirection: Bool {
        switch self {
        case .amount, .duration: true
        case .timeTarget: false
        }
    }
}

enum QuantityDirection: String, Codable, CaseIterable, Identifiable {
    case cap      // at most
    case target   // at least

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cap: "Cap"
        case .target: "Target"
        }
    }
}

/// How a target's tolerance is read: a fixed amount, or a percentage of the goal.
enum ToleranceMode: String, Codable, CaseIterable, Identifiable {
    case absolute
    case percent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .absolute: "Absolute"
        case .percent: "Percent"
        }
    }
}

/// How an item is logged on the Record tab. Separate from what the item measures: an NFC tap
/// can log a check or a clock time, for example.
enum TrackingMethod: String, Codable, CaseIterable, Identifiable {
    case check
    case number
    case timer
    case nfc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .check: "Check"
        case .number: "Number"
        case .timer: "Timer"
        case .nfc: "NFC"
        }
    }

    var systemImage: String {
        switch self {
        case .check: "checkmark.circle"
        case .number: "number"
        case .timer: "timer"
        case .nfc: "wave.3.right"
        }
    }

    /// Methods that make sense for an item with this kind of tracking.
    static func options(for trackingType: TrackingType, quantitySubtype: QuantitySubtype?) -> [TrackingMethod] {
        guard trackingType == .quantity else { return [.check, .nfc] }
        switch quantitySubtype {
        case .duration?: return [.timer, .number]
        case .timeTarget?: return [.number, .nfc]
        default: return [.number]
        }
    }
}

/// Units for quantity-amount items. Fixed set for now — add cases here as new units come up.
enum QuantityUnit: String, Codable, CaseIterable, Identifiable {
    case steps
    case calories
    case times
    case reps
    case pages
    case ounces
    case miles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: "Steps"
        case .calories: "Calories"
        case .times: "Times"
        case .reps: "Reps"
        case .pages: "Pages"
        case .ounces: "Ounces"
        case .miles: "Miles"
        }
    }
}
