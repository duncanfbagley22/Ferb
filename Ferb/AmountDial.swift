import SwiftUI

/// A drag-around ring for amount and duration inputs. One lap is the goal. The solid arc is what's
/// already logged this period, the lighter arc is what's about to be added, and the handle sits at the
/// new total. Dragging snaps the amount to add to `step` (1, 10 or 100, set by goal size) and writes
/// it to `draft.numberText`, so the arrows and the typed field stay in step with it. A lap stops at
/// the goal; going past it is done with the arrows or by typing.
struct AmountDial: View {
    let target: Target
    @Bindable var draft: LogDraft
    /// Amount already counted on top of the typed one: the running timer's minutes (0 for plain amounts).
    var extraAmount: Double = 0
    /// Show this period's logged total instead of the current period's (used when backdating a log).
    var period: TargetPeriod? = nil
    let step: Double
    var size: CGFloat = 170

    /// Where the finger last was on the ring (0...1, clockwise from the top), used to stop at the
    /// top instead of jumping from full to empty when the finger crosses 12 o'clock.
    @State private var lastTouch: Double?

    private let lineWidth: CGFloat = 16
    private var ringSize: CGFloat { size - lineWidth }

    /// Logged so far in the period being logged to: the one passed in, else the current one (0 when nothing is in yet).
    private var logged: Double {
        if let period { return period.loggedValue ?? 0 }
        return target.recentPeriods(1).first(where: \.isCurrent)?.loggedValue ?? 0
    }

    private var goal: Double? {
        guard let value = target.value, value > 0 else { return nil }
        return value
    }

    /// What a full lap stands for: the goal, or ten steps when the target has none.
    private var scale: Double { goal ?? step * 10 }

    /// What logging would add right now: the typed amount plus any running timer.
    private var pending: Double { extraAmount + (draft.number ?? 0) }

    var body: some View {
        let logged = self.logged
        let total = logged + pending
        let loggedFraction = min(logged / scale, 1)
        let totalFraction = min(total / scale, 1)
        let angle = Angle.degrees(totalFraction * 360)

        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: lineWidth)
                .frame(width: ringSize, height: ringSize)

            if totalFraction > 0 {
                Circle()
                    .trim(from: 0, to: totalFraction)
                    .stroke(Color.goalMet.opacity(0.4), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringSize, height: ringSize)
            }
            if loggedFraction > 0 {
                Circle()
                    .trim(from: 0, to: loggedFraction)
                    .stroke(Color.goalMet, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringSize, height: ringSize)
            }

            Circle()
                .fill(.white)
                .overlay(Circle().stroke(Color.goalMet, lineWidth: 3))
                .shadow(radius: 2)
                .frame(width: lineWidth + 8, height: lineWidth + 8)
                .offset(
                    x: (ringSize / 2) * CGFloat(sin(angle.radians)),
                    y: -(ringSize / 2) * CGFloat(cos(angle.radians))
                )

            centerText(total: total)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag(to: $0.location) }
                .onEnded { _ in lastTouch = nil }
        )
        .sensoryFeedback(.selection, trigger: draft.numberText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amount to add")
        .accessibilityValue("\(Target.formatted(pending)) to add, \(Target.formatted(total)) total")
        .accessibilityAdjustableAction { direction in
            let next = max(0, (draft.number ?? 0) + (direction == .increment ? step : -step))
            set(next)
        }
    }

    private func centerText(total: Double) -> some View {
        VStack(spacing: 2) {
            Text(Target.formatted(total))
                .font(.system(size: 34, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // Always laid out, so the numbers above don't shift when an amount appears.
            Text("+" + Target.formatted(pending))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.goalMet)
                .opacity(pending > 0 ? 1 : 0)
        }
        .frame(width: ringSize - lineWidth * 2 - 8)
        .allowsHitTesting(false)
    }

    /// "of 10,000 steps", or just the unit when the target has no goal.
    private var subtitle: String {
        let unit = target.logUnitLabel
        guard let goal else { return unit }
        return ("of \(Target.formatted(goal)) \(unit)").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Dragging

    private func drag(to point: CGPoint) {
        let dx = point.x - size / 2
        let dy = point.y - size / 2
        guard dx != 0 || dy != 0 else { return }

        var angle = atan2(dx, -dy)              // 0 at the top, clockwise
        if angle < 0 { angle += 2 * .pi }
        var fraction = angle / (2 * .pi)

        // Hold at full / empty when the finger crosses the top, rather than wrapping around.
        if let last = lastTouch {
            if last > 0.75 && fraction < 0.25 { fraction = 1 }
            else if last < 0.25 && fraction > 0.75 { fraction = 0 }
            else if last == 1 && fraction < 0.5 { fraction = 1 }
            else if last == 0 && fraction > 0.5 { fraction = 0 }
        }
        lastTouch = fraction

        // The handle marks the new total, so the amount to add is the total minus what's in already.
        var add = fraction * scale - logged - extraAmount
        if fraction < 0.985 {
            add = (add / step).rounded() * step     // snap to the step
        }                                            // at the very top, land exactly on the goal
        set(max(0, add))
    }

    private func set(_ amount: Double) {
        let clean = (amount * 100).rounded() / 100
        draft.numberText = clean == 0 ? "" : (clean == clean.rounded() ? String(Int(clean)) : String(clean))
    }
}
