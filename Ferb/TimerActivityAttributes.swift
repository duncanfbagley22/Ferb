import ActivityKit
import Foundation

// IMPORTANT: this is an identical copy of the struct in
// FerbTimerWidget/FerbTimerWidgetLiveActivity.swift. The type name, property names and types
// must match exactly in both places, or the Live Activity silently stops working.
// Change both together.
struct FerbTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// When the clock would have started if it had never paused (now minus banked time).
        var startedAt: Date
        /// Set while paused; the clock freezes at this moment. nil while running.
        var pausedAt: Date?
    }

    /// The item being timed, e.g. "Meditate".
    var itemName: String
    /// Identifies which target's timer this is, so the app can find its activity again.
    var targetKey: String
}
