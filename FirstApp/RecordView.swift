import SwiftUI
import SwiftData

/// Record tab hub: pick how you want to log, then pick the item and log it.
struct RecordView: View {
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(TrackingMethod.allCases) { method in
                        NavigationLink(value: method) {
                            VStack(spacing: 12) {
                                Image(systemName: method.systemImage)
                                    .font(.system(size: 40))
                                Text(method.title)
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity, minHeight: 140)
                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Record")
            .navigationDestination(for: TrackingMethod.self) { method in
                RecordMethodView(method: method)
            }
        }
    }
}

/// One logging method: choose an active target whose item uses this method, enter the
/// value, then reset or confirm. Confirming saves a log and returns to the hub.
struct RecordMethodView: View {
    let method: TrackingMethod

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Target.startDate) private var allTargets: [Target]

    @State private var selectedTarget: Target?
    @State private var isChecked = false
    @State private var numberText = ""
    @State private var timeOfDay = Date.now
    @State private var hasScanned = false

    private var targets: [Target] {
        allTargets.filter { $0.isActive() && $0.item?.effectiveMethod == method }
    }

    private var activeTarget: Target? {
        if let selectedTarget, targets.contains(selectedTarget) { return selectedTarget }
        return targets.first
    }

    private var isTimeTarget: Bool {
        activeTarget?.item?.quantitySubtype == .timeTarget
    }

    var body: some View {
        VStack(spacing: 24) {
            if targets.isEmpty {
                ContentUnavailableView(
                    "Nothing to log",
                    systemImage: method.systemImage,
                    description: Text("No active targets use \(method.title.lowercased()) logging.")
                )
            } else {
                Picker("Target", selection: Binding(get: { activeTarget }, set: { selectedTarget = $0 })) {
                    ForEach(targets) { target in
                        Text("\(target.item?.name ?? "Item") · \(target.cadenceTitle)")
                            .tag(Optional(target))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
                content
                Spacer()
                buttons
            }
        }
        .padding()
        .navigationTitle(method.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedTarget) { reset() }
    }

    // MARK: - Method screens

    @ViewBuilder
    private var content: some View {
        switch method {
        case .check: checkContent
        case .number: numberContent
        case .timer: timerContent
        case .nfc: nfcContent
        }
    }

    private var checkContent: some View {
        let avoided = activeTarget?.item?.binarySubtype == .avoidedIt
        return bigCircle(systemImage: "checkmark", isOn: isChecked) {
            isChecked.toggle()
        } caption: {
            isChecked ? (avoided ? "Avoided" : "Done") : "Tap to mark"
        }
    }

    private var nfcContent: some View {
        // TODO: real CoreNFC scanning. Needs a physical iPhone, so this fakes a scan with a tap.
        bigCircle(systemImage: "wave.3.right", isOn: hasScanned) {
            hasScanned.toggle()
        } caption: {
            hasScanned ? "Scanned" : "Tap to simulate a scan"
        }
    }

    @ViewBuilder
    private var numberContent: some View {
        if isTimeTarget {
            DatePicker("Time", selection: $timeOfDay, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
        } else {
            HStack(spacing: 16) {
                Button { adjust(by: -step) } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .frame(width: 44, height: 64)
                }
                .buttonStyle(.bordered)

                VStack(spacing: 4) {
                    TextField("0", text: $numberText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 48, weight: .bold))
                    Text(unitLabel)
                        .foregroundStyle(.secondary)
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
    }

    private var timerContent: some View {
        VStack(spacing: 16) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = elapsed(at: context.date)
                Button { toggleTimer() } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: timerProgress(seconds))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(clockString(seconds))
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                    }
                    .frame(width: 240, height: 240)
                }
                .buttonStyle(.plain)
            }
            if let started = activeTarget?.timerStartedAt {
                Text("Running since \(started.formatted(Calendar.current.isDateInToday(started) ? .dateTime.hour().minute() : .dateTime.month(.abbreviated).day().hour().minute())) · tap to pause")
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap to start")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bigCircle(
        systemImage: String,
        isOn: Bool,
        action: @escaping () -> Void,
        caption: () -> String
    ) -> some View {
        VStack(spacing: 16) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 80))
                    .foregroundStyle(.primary)
                    .frame(width: 220, height: 220)
                    .background((isOn ? Color.green : Color.red).opacity(0.25), in: Circle())
            }
            .buttonStyle(.plain)
            Text(caption())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack(spacing: 12) {
            Button { resetAll() } label: {
                Text("Reset").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button { confirm() } label: {
                Text("Confirm").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canConfirm)
        }
        .controlSize(.large)
    }

    private var canConfirm: Bool {
        guard activeTarget != nil else { return false }
        switch method {
        case .check: return isChecked
        case .number: return isTimeTarget || numberValue != nil
        case .timer: return (activeTarget?.timerAccumulated ?? 0) > 0 || activeTarget?.timerStartedAt != nil
        case .nfc: return hasScanned
        }
    }

    private func confirm() {
        guard let target = activeTarget else { return }
        let value = logValue()
        modelContext.insert(Log(target: target, value: value))
        if method == .timer { clearTimer(on: target) }
        try? modelContext.save()
        dismiss()
    }

    /// The Reset button: clears the entry fields, and for the timer method also the saved timer.
    private func resetAll() {
        reset()
        if method == .timer, let target = activeTarget { clearTimer(on: target) }
    }

    /// Clears the on-screen fields only. A target's saved timer is left alone, so switching
    /// targets doesn't wipe a timer that's running on another one.
    private func reset() {
        isChecked = false
        numberText = ""
        timeOfDay = .now
        hasScanned = false
    }

    /// Nil for plain checks; minutes for timers; the typed number; or the clock time as
    /// minutes since midnight for time targets.
    private func logValue() -> Double? {
        switch method {
        case .check: return nil
        case .number: return isTimeTarget ? minutesSinceMidnight(timeOfDay) : numberValue
        case .timer: return elapsed(at: .now) / 60
        case .nfc: return isTimeTarget ? minutesSinceMidnight(.now) : nil
        }
    }

    // MARK: - Number helpers

    private var numberValue: Double? {
        Double(numberText.trimmingCharacters(in: .whitespaces))
    }

    /// Step size for the arrows, scaled to the goal so 10,000 steps isn't tapped one at a time.
    private var step: Double {
        let goal = activeTarget?.value ?? 1
        if goal >= 1000 { return 100 }
        return goal >= 100 ? 10 : 1
    }

    private var unitLabel: String {
        guard let item = activeTarget?.item else { return "" }
        switch item.quantitySubtype {
        case .amount?: return item.unit?.title.lowercased() ?? ""
        case .duration?: return "min"
        default: return ""
        }
    }

    private func adjust(by delta: Double) {
        let next = max(0, (numberValue ?? 0) + delta)
        numberText = next == next.rounded() ? String(Int(next)) : String(next)
    }

    private func minutesSinceMidnight(_ date: Date) -> Double {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    // MARK: - Timer helpers

    private func elapsed(at date: Date) -> TimeInterval {
        guard let target = activeTarget else { return 0 }
        return target.timerAccumulated + (target.timerStartedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    private func toggleTimer() {
        guard let target = activeTarget else { return }
        if target.timerStartedAt != nil {
            target.timerAccumulated = elapsed(at: .now)
            target.timerStartedAt = nil
        } else {
            target.timerStartedAt = .now
        }
        try? modelContext.save()
    }

    private func clearTimer(on target: Target) {
        target.timerAccumulated = 0
        target.timerStartedAt = nil
    }

    /// Fraction of the goal reached, when the target has a duration goal.
    private func timerProgress(_ seconds: TimeInterval) -> Double {
        guard let goal = activeTarget?.value, goal > 0 else { return 0 }
        return min(1, seconds / (goal * 60))
    }

    private func clockString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
