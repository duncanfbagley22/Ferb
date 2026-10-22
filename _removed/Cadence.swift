import Foundation

enum Cadence: String, CaseIterable, Codable, Identifiable {
    case once
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .once: "One time"
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }
}
