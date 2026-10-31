import Foundation
import SwiftData

/// A free-form note you write for yourself, kept under Settings → Notes.
@Model
final class Note {
    var body: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(body: String = "", createdAt: Date = .now) {
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

extension Note {
    private var lines: [Substring] {
        body.split(separator: "\n", omittingEmptySubsequences: true)
    }

    /// The first line, shown as the note's title in the list.
    var title: String {
        guard let first = lines.first else { return "New note" }
        return first.trimmingCharacters(in: .whitespaces)
    }

    /// The rest of the note after the first line, for the list preview.
    var preview: String {
        lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    var isBlank: Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
