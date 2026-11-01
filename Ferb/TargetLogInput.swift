import SwiftUI
import SwiftData

/// What a log entry asks for, based on how the target's item is tracked.
nonisolated enum LogInputKind {
    case check          // a yes/no
    case amount         // a number (steps, reps...)
    case duration       // minutes typed in
    case durationTimer  // minutes typed in and/or a start-pause timer, added together
    case time           // a clock time
}

/// What logging would record right now, or why it can't yet.
enum LogResolution {
    case value(Double?)
    case invalid(String)
}

// MARK: - Target helpers

extension Target {
    var logInputKind: LogInputKind {
        guard let item, item.trackingType == .quantity else { return .check }
        switch item.quantitySubtype {
        case .timeTarget?: return .time
        case .duration?: return item.effectiveMethod == .timer ? .durationTimer : .duration
        default: return .amount
        }
    }

    /// The unit shown under the number field ("steps", "min", or nothing).
    var logUnitLabel: String {
        guard let item else { return "" }
        switch item.quantitySubtype {
        case .amount?: return item.unitName
        case .duration?: return "min"
        default: return ""
        }
    }

    /// "3,000 steps logged so far" when part of the period's amount is already in.
    var loggedSoFarText: String? {
        let kind = logInputKind
        guard kind == .amount || kind == .duration || kind == .durationTimer,
              let value = recentPeriods(1).first(where: \.isCurrent)?.loggedValue else { return nil }
        return "\(Target.formatted(value)) \(logUnitLabel) logged so far"
            .replacingOccurrences(of: "  ", with: " ")
    }

    /// Seconds on the saved timer: banked time plus the current run, if one is going.
    func timerSeconds(at date: Date = .now) -> TimeInterval {
        timerAccumulated + (timerStartedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggleTimer(in context: ModelContext) {
        if timerStartedAt != nil {
            timerAccumulated = timerSeconds()
            timerStartedAt = nil
        } else {
            timerStartedAt = .now
        }
        try? context.save()
        syncTimerActivity()
    }

    func clearTimer() {
        timerAccumulated = 0
        timerStartedAt = nil
        TimerActivity.end(key: timerActivityKey)
    }

    /// Identifies this target to its Live Activity. Keys are sorted so the same target always
    /// produces the same string; otherwise pausing couldn't find the banner that play started.
    private var timerActivityKey: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(persistentModelID))?.base64EncodedString() ?? ""
    }

    /// Mirrors the saved timer onto the lock screen / Dynamic Island banner.
    private func syncTimerActivity() {
        guard let name = item?.name, !timerActivityKey.isEmpty else { return }
        if let started = timerStartedAt {
            // Running: the clock reads banked time plus this run.
            TimerActivity.start(
                key: timerActivityKey,
                itemName: name,
                startedAt: started.addingTimeInterval(-timerAccumulated)
            )
        } else {
            // Paused: freeze the clock at the banked time.
            let now = Date.now
            TimerActivity.pause(
                key: timerActivityKey,
                startedAt: now.addingTimeInterval(-timerAccumulated),
                pausedAt: now
            )
        }
    }
}

// MARK: - Draft

/// What's been typed or picked for the log entry in progress. Both Quick update and Log now
/// hold one, so they read the same inputs and decide the same way what gets logged.
@Observable
final class LogDraft {
    var numberText = ""
    var timeOfDay = Date.now

    var number: Double? {
        Double(numberText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    func reset() {
        numberText = ""
        timeOfDay = .now
    }

    /// What logging would record for `target` right now, or why it can't yet.
    func resolve(_ target: Target) -> LogResolution {
        switch target.logInputKind {
        case .check:
            return .value(nil)
        case .time:
            return .value(Self.minutesSinceMidnight(timeOfDay))
        case .amount, .duration:
            guard let number, number > 0 else { return .invalid("Enter a number first") }
            return .value(number)
        case .durationTimer:
            let total = target.timerSeconds() / 60 + (number ?? 0)
            return total > 0 ? .value(total) : .invalid("Start the timer or add minutes first")
        }
    }

    static func minutesSinceMidnight(_ date: Date) -> Double {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
}

// MARK: - Inputs

/// The input area for one target: a check prompt, number field, timer plus minutes, or a
/// clock-time wheel, depending on how its item is tracked.
struct TargetLogInputs: View {
    let target: Target
    @Bindable var draft: LogDraft
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        switch target.logInputKind {
        case .check:
            let avoided = target.item?.binarySubtype == .avoidedIt
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text(avoided ? "Did you avoid it?" : "Did you do it?")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)

        case .amount, .duration:
            numberField(unit: target.logUnitLabel, prompt: "0")

        case .durationTimer:
            VStack(spacing: 16) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = target.timerSeconds(at: context.date)
                    let total = seconds / 60 + (draft.number ?? 0)
                    VStack(spacing: 8) {
                        HStack(spacing: 16) {
                            Button { target.toggleTimer(in: modelContext) } label: {
                                Image(systemName: target.timerStartedAt == nil ? "play.fill" : "pause.fill")
                                    .font(.title2)
                                    .frame(width: 52, height: 52)
                                    .background(Color.accentColor.opacity(0.2), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(target.timerStartedAt == nil ? "Start timer" : "Pause timer")

                            Text(clockString(seconds))
                                .font(.system(size: 36, weight: .bold, design: .monospaced))
                        }
                        Text("\(Int(total.rounded())) min total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                numberField(unit: "min to add", prompt: "0")
            }
            .frame(maxWidth: .infinity)

        case .time:
            DatePicker("Time", selection: $draft.timeOfDay, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
        }
    }

    private func numberField(unit: String, prompt: String) -> some View {
        HStack(spacing: 16) {
            Button { adjust(by: -step) } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .frame(width: 44, height: 64)
            }
            .buttonStyle(.bordered)

            VStack(spacing: 4) {
                TextField(prompt, text: $draft.numberText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 44, weight: .bold))
                if !unit.isEmpty {
                    Text(unit)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            Button { adjust(by: step) } label: {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .frame(width: 44, height: 64)
            }
            .buttonStyle(.bordered)
        }
    }

    /// Step size for the arrows, scaled to the goal so 10,000 steps isn't tapped one at a time.
    private var step: Double {
        let goal = target.value ?? 1
        if goal >= 1000 { return 100 }
        return goal >= 100 ? 10 : 1
    }

    private func adjust(by delta: Double) {
        let next = max(0, (draft.number ?? 0) + delta)
        draft.numberText = next == next.rounded() ? String(Int(next)) : String(next)
    }

    private func clockString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
