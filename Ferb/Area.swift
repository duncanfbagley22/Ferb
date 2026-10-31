import Foundation

enum Area: String, CaseIterable, Codable, Identifiable {
    case surface
    case structure
    case internals
    case regulation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .surface: "Surface"
        case .structure: "Structure"
        case .internals: "Internal"
        case .regulation: "Regulation"
        }
    }

    var letter: String {
        switch self {
        case .surface: "A"
        case .structure: "B"
        case .internals: "C"
        case .regulation: "D"
        }
    }
}
