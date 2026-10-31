import ActivityKit
import WidgetKit
import SwiftUI

// IMPORTANT: the app has an identical copy of this struct in Ferb/Ferb/TimerActivityAttributes.swift.
// The type name, property names and types must match exactly in both places, or the
// Live Activity silently stops working. Change both together.
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

/// The ticking clock. The system draws and updates this itself, so it keeps counting while
/// the app is closed. While paused it holds still at `pausedAt`.
private struct TimerClock: View {
    let state: FerbTimerAttributes.ContentState

    var body: some View {
        Text(
            timerInterval: state.startedAt...state.startedAt.addingTimeInterval(24 * 60 * 60),
            pauseTime: state.pausedAt,
            countsDown: false,
            showsHours: false
        )
        .monospacedDigit()
    }
}

struct FerbTimerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FerbTimerAttributes.self) { context in
            // Lock screen and banner
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                    Text(context.attributes.itemName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(context.state.pausedAt == nil ? "Running" : "Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TimerClock(state: context.state)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.itemName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.pausedAt == nil ? "Running" : "Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TimerClock(state: context.state)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                TimerClock(state: context.state)
                    .font(.caption.weight(.semibold))
                    .frame(width: 52, alignment: .trailing)
            } minimal: {
                Image(systemName: context.state.pausedAt == nil ? "timer" : "pause.fill")
            }
        }
    }
}

extension FerbTimerAttributes {
    fileprivate static var preview: FerbTimerAttributes {
        FerbTimerAttributes(itemName: "Meditate", targetKey: "preview")
    }
}

extension FerbTimerAttributes.ContentState {
    fileprivate static var running: FerbTimerAttributes.ContentState {
        FerbTimerAttributes.ContentState(startedAt: .now.addingTimeInterval(-125), pausedAt: nil)
    }

    fileprivate static var paused: FerbTimerAttributes.ContentState {
        FerbTimerAttributes.ContentState(
            startedAt: .now.addingTimeInterval(-300),
            pausedAt: .now.addingTimeInterval(-120)
        )
    }
}

#Preview("Lock screen", as: .content, using: FerbTimerAttributes.preview) {
    FerbTimerWidgetLiveActivity()
} contentStates: {
    FerbTimerAttributes.ContentState.running
    FerbTimerAttributes.ContentState.paused
}
