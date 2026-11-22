import SwiftUI

/// The check card for yes/no targets: press and hold the circle to log it. A dark green ring fills
/// while you hold (about 0.6 s), then the circle fills solid and `onComplete` runs. Letting go early
/// cancels. The same dark green and haptics as the amount dial.
struct HoldToCompleteCheck: View {
    let prompt: String
    let onComplete: () -> Void

    private let holdDuration = 0.6
    private let lineWidth: CGFloat = 8

    @State private var progress: CGFloat = 0
    @State private var isHolding = false
    @State private var completed = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: lineWidth)
                Circle()
                    .fill(Color.goalMet.opacity(completed ? 1 : 0))
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.goalMet, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(completed ? Color.white : Color.secondary)
            }
            .frame(width: 110, height: 110)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 10) {
                complete()
            } onPressingChanged: { pressing in
                isHolding = pressing
                if pressing {
                    withAnimation(.linear(duration: holdDuration)) { progress = 1 }
                } else if !completed {
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isHolding) { _, holding in holding }
            .sensoryFeedback(.success, trigger: completed) { _, done in done }

            Text(prompt)
                .font(.headline)
            Text("Hold to log")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(prompt)
        .accessibilityHint("Logs it")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { complete() }
    }

    private func complete() {
        withAnimation(.easeOut(duration: 0.15)) {
            progress = 1
            completed = true
        }
        onComplete()
    }
}
