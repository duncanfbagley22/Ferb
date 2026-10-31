import ActivityKit
import Foundation

/// Mirrors a target's saved timer onto a Live Activity (lock screen and Dynamic Island).
/// Only one timer shows at a time: starting or resuming one replaces any other's banner.
/// Everything here is best-effort. If Live Activities are off or can't start, the in-app
/// timer is unaffected.
enum TimerActivity {
    /// The timer is running: show it, replacing any other timer's banner.
    static func start(key: String, itemName: String, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task {
            let content = ActivityContent(
                state: FerbTimerAttributes.ContentState(startedAt: startedAt, pausedAt: nil),
                staleDate: nil
            )
            var found = false
            for activity in Activity<FerbTimerAttributes>.activities {
                if activity.attributes.targetKey == key {
                    found = true
                    await activity.update(content)
                } else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            if !found {
                _ = try? Activity<FerbTimerAttributes>.request(
                    attributes: FerbTimerAttributes(itemName: itemName, targetKey: key),
                    content: content,
                    pushType: nil
                )
            }
        }
    }

    /// The timer is paused: freeze this timer's banner if it has one. A banner showing a
    /// different timer is left alone.
    static func pause(key: String, startedAt: Date, pausedAt: Date) {
        Task {
            let content = ActivityContent(
                state: FerbTimerAttributes.ContentState(startedAt: startedAt, pausedAt: pausedAt),
                staleDate: nil
            )
            for activity in Activity<FerbTimerAttributes>.activities
            where activity.attributes.targetKey == key {
                await activity.update(content)
            }
        }
    }

    /// The timer was logged or reset: remove its banner.
    static func end(key: String) {
        Task {
            for activity in Activity<FerbTimerAttributes>.activities
            where activity.attributes.targetKey == key {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
