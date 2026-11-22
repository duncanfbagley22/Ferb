import SwiftUI
import SwiftData

/// A single target: its goal, one numbered row per period with a done mark, and a stats
/// block (streaks, completion, a per-period chart for amounts). The stats block is pinned to
/// the bottom; only the period list above it scrolls.
struct TargetDetailView: View {
    let target: Target
    @State private var showingEdit = false
    @State private var showingLog = false
    @State private var selectedPeriod: TargetPeriod?

    var body: some View {
        let periods = target.periods()
        let doneCount = periods.filter { $0.result == .done }.count

        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(target.cadenceTitle)
                                .font(.headline)
                            if let summary = target.valueSummary {
                                Text(summary)
                            }
                            Text(target.dateRangeText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(target.isRolling == true
                                ? "\(doneCount) of \(periods.count) days covered"
                                : "\(doneCount) of \(periods.count) periods done")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        LazyVStack(spacing: 0) {
                            ForEach(periods) { period in
                                Button { selectedPeriod = period } label: {
                                    PeriodRow(period: period, target: target)
                                }
                                .buttonStyle(.plain)
                                // Only days that haven't started are locked. A rolling target's early days
                                // also come back as .upcoming (no verdict yet) but have logs to edit.
                                .disabled(period.start > Date.now)
                                .id(period.number)
                            }
                        }
                    }
                    .padding()
                }
                .onAppear {
                    if let current = periods.first(where: \.isCurrent) {
                        proxy.scrollTo(current.number, anchor: .center)
                    }
                }
            }

            TargetStatsBlock(target: target, periods: periods)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom)
        }
        .navigationTitle(target.item?.name ?? "Target")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if target.isActive() {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log", systemImage: "plus") { showingLog = true }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddTargetView(editing: target)
        }
        .sheet(isPresented: $showingLog) {
            LogNowView(target: target)
        }
        .sheet(item: $selectedPeriod) { period in
            PeriodLogsView(target: target, period: period)
        }
    }
}

private struct PeriodRow: View {
    let period: TargetPeriod
    let target: Target

    private var color: Color {
        switch period.result {
        case .done: Color.goalMet
        case .missed: Color.goalMissed
        case .open, .upcoming: .gray
        }
    }

    private var dateText: String {
        let calendar = Calendar.current
        let start = period.start.formatted(.dateTime.month(.abbreviated).day())
        let last = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.end
        if calendar.isDate(last, inSameDayAs: period.start) { return start }
        return "\(start) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var valueText: String? {
        guard let value = period.loggedValue, let item = target.item,
              let subtype = item.quantitySubtype else { return nil }
        switch subtype {
        case .amount: return "\(Target.formatted(value)) \(item.unitName)"
        case .duration: return "\(Target.formatted(value)) min"
        case .timeTarget: return Target.clock(minutes: Int(value))
        }
    }

    private var markName: String {
        switch period.result {
        case .done: "checkmark.circle.fill"
        case .missed: "xmark.circle"
        case .open, .upcoming: "circle"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("\(period.number)")
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(dateText)
                    if let valueText {
                        Text(valueText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: markName)
                    .font(.title3)
                    .foregroundStyle(period.result == .upcoming ? Color.secondary : color)
            }
            .padding(.vertical, 10)
            .opacity(period.result == .upcoming ? 0.5 : 1)

            Divider()
        }
    }
}

/// The logs behind one period: tap one to edit it, swipe to delete it, or add one, including
/// for a day that has already passed.
private struct PeriodLogsView: View {
    let target: Target
    let period: TargetPeriod

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var editingLog: Log?
    @State private var showingAdd = false

    private var logs: [Log] {
        target.logs
            .filter {
                let day = target.countingDate(of: $0, calendar: .current)
                return day >= period.start && day < period.end
            }
            .sorted { $0.completedAt < $1.completedAt }
    }

    private var title: String {
        let calendar = Calendar.current
        let start = period.start.formatted(.dateTime.month(.abbreviated).day())
        let last = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.end
        if calendar.isDate(last, inSameDayAs: period.start) { return start }
        return "\(start) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if logs.isEmpty {
                        Text("No logs in this period")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(logs) { log in
                        Button { editingLog = log } label: { row(for: log) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    delete(log)
                                }
                            }
                    }
                } footer: {
                    if !logs.isEmpty {
                        Text("Tap a log to edit it, or swipe to delete it.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add log", systemImage: "plus") { showingAdd = true }
                }
            }
            .sheet(item: $editingLog) { log in
                LogEditorView(target: target, period: period, editing: log)
            }
            .sheet(isPresented: $showingAdd) {
                AddLogView(target: target, period: period)
            }
        }
    }

    private func row(for log: Log) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(log.completedAt.formatted(date: .abbreviated, time: .shortened))
                if let text = valueText(for: log) {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func valueText(for log: Log) -> String? {
        guard let value = log.value, let item = target.item,
              let subtype = item.quantitySubtype else { return nil }
        switch subtype {
        case .amount: return "\(Target.formatted(value)) \(item.unitName)"
        case .duration: return "\(Target.formatted(value)) min"
        case .timeTarget: return Target.clock(minutes: Int(value))
        }
    }

    private func delete(_ log: Log) {
        target.remove(log, in: modelContext)
    }
}

/// Adds a log to a period the Quick update way: pick the day (only when the period spans several),
/// then use the same inputs (hold-to-complete check, amount dial, time wheel) and tap Log. Check,
/// amount and duration logs are stamped now for today, or noon for an earlier day; time targets use
/// the time on the wheel. Editing an existing log still uses `LogEditorView`, which keeps the exact time.
private struct AddLogView: View {
    let target: Target
    let period: TargetPeriod

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var draft = LogDraft()
    @State private var day: Date
    @State private var warning: String?

    private let calendar = Calendar.current

    init(target: Target, period: TargetPeriod) {
        self.target = target
        self.period = period
        let calendar = Calendar.current
        let lastDay = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.start
        _day = State(initialValue: max(period.start, min(lastDay, calendar.startOfDay(for: .now))))
    }

    private var periodDays: Int {
        calendar.dateComponents([.day], from: period.start, to: period.end).day ?? 1
    }

    /// Days of the period that have started: logs can't be added to the future.
    private var dayRange: ClosedRange<Date> {
        let lastDay = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.start
        let latest = min(lastDay, calendar.startOfDay(for: .now))
        return period.start...max(period.start, latest)
    }

    /// The calendar day being logged for.
    private var logDay: Date {
        calendar.startOfDay(for: periodDays > 1 ? day : period.start)
    }

    private var dayTitle: String {
        logDay.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// What would be logged, or why it can't be yet. A timer target takes typed minutes here:
    /// the running timer belongs to today, not to a past day.
    private func resolveValue() -> LogResolution {
        if target.logInputKind == .durationTimer {
            guard let number = draft.number, number > 0 else { return .invalid("Add minutes first") }
            return .value(number)
        }
        return draft.resolve(target)
    }

    /// When the log is stamped: the wheel's time for time targets, otherwise now for today or
    /// noon for an earlier day.
    private func completedAt(for value: Double?) -> Date {
        if target.logInputKind == .time, let value {
            let minutes = Int(value)
            var base = logDay
            // An early-morning time on an evening goal counts for the night before, so it is
            // stamped on the next calendar day.
            if target.isEveningTimeGoal && minutes < 12 * 60 {
                base = calendar.date(byAdding: .day, value: 1, to: base) ?? base
            }
            return calendar.date(byAdding: .minute, value: minutes, to: base) ?? base
        }
        if calendar.isDateInToday(logDay) { return .now }
        return calendar.date(byAdding: .hour, value: 12, to: logDay) ?? logDay
    }

    private func save() {
        switch resolveValue() {
        case .invalid(let message):
            warning = message
        case .value(let value):
            let at = completedAt(for: value)
            if at > Date.now.addingTimeInterval(60) {
                warning = "That time hasn't happened yet."
                return
            }
            target.record(value: value, at: at, in: modelContext)
            dismiss()
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if periodDays > 1 {
                        DatePicker("Day", selection: $day, in: dayRange, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    } else {
                        Text(dayTitle)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }

                    TargetLogInputs(
                        target: target,
                        draft: draft,
                        onComplete: save,
                        period: period,
                        backdating: true
                    )

                    if let warning {
                        Text(warning)
                            .font(.footnote)
                            .foregroundStyle(Color.goalMissed)
                    }

                    Button(action: save) {
                        Text("Log")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.goalMet)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: day) { warning = nil }
            .onChange(of: draft.numberText) { warning = nil }
            .onChange(of: draft.timeOfDay) { warning = nil }
            .navigationTitle("Add log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Edits an existing log (adding now goes through `AddLogView`). Quantity targets ask for the
/// number; time targets ask for the clock time; everything else just asks when.
private struct LogEditorView: View {
    let target: Target
    let period: TargetPeriod
    let editing: Log?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var day: Date
    @State private var moment: Date
    @State private var timeOfDay: Date
    @State private var valueText: String

    private let calendar = Calendar.current

    init(target: Target, period: TargetPeriod, editing: Log?) {
        self.target = target
        self.period = period
        self.editing = editing

        let calendar = Calendar.current
        let now = Date.now
        let lastDay = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.start
        let latestDay = min(lastDay, calendar.startOfDay(for: now))

        if let log = editing {
            let minutes: Int
            if let value = log.value {
                minutes = Int(value)
            } else {
                let parts = calendar.dateComponents([.hour, .minute], from: log.completedAt)
                minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
            _day = State(initialValue: calendar.startOfDay(for: target.countingDate(of: log, calendar: calendar)))
            _moment = State(initialValue: log.completedAt)
            _timeOfDay = State(initialValue: calendar.date(
                from: DateComponents(hour: (minutes / 60) % 24, minute: minutes % 60)
            ) ?? now)
            _valueText = State(initialValue: log.value.map(Self.plainNumber) ?? "")
        } else {
            // New logs default to now in the current period, or noon on the period's last day.
            let isCurrent = period.start <= now && now < period.end
            _day = State(initialValue: latestDay)
            _moment = State(initialValue: isCurrent
                ? now
                : (calendar.date(byAdding: .hour, value: 12, to: lastDay) ?? lastDay))
            _timeOfDay = State(initialValue: now)
            _valueText = State(initialValue: "")
        }
    }

    @MainActor
    private static func plainNumber(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(number)
    }

    private var isQuantity: Bool { target.item?.trackingType == .quantity }
    private var isTimeTarget: Bool { isQuantity && target.item?.quantitySubtype == .timeTarget }
    private var needsNumber: Bool { isQuantity && !isTimeTarget }

    private var periodDays: Int {
        calendar.dateComponents([.day], from: period.start, to: period.end).day ?? 1
    }

    /// Days of the period that have started: logs can't be added to the future.
    private var dayRange: ClosedRange<Date> {
        let lastDay = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.start
        let latest = min(lastDay, calendar.startOfDay(for: .now))
        return period.start...max(period.start, latest)
    }

    private var momentRange: ClosedRange<Date> {
        let latest = min(period.end.addingTimeInterval(-1), .now)
        return period.start...max(period.start, latest)
    }

    private var number: Double? {
        Double(valueText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private var unitLabel: String {
        guard let item = target.item else { return "" }
        switch item.quantitySubtype {
        case .amount?: return item.unitName
        case .duration?: return "min"
        default: return ""
        }
    }

    /// When and what this log would be saved as.
    private func resolved() -> (completedAt: Date, value: Double?) {
        if isTimeTarget {
            let parts = calendar.dateComponents([.hour, .minute], from: timeOfDay)
            let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            var base = calendar.startOfDay(for: periodDays > 1 ? day : period.start)
            // An early-morning time on an evening goal counts for the night before, so it
            // is stamped on the next calendar day.
            if target.isEveningTimeGoal && minutes < 12 * 60 {
                base = calendar.date(byAdding: .day, value: 1, to: base) ?? base
            }
            return (calendar.date(byAdding: .minute, value: minutes, to: base) ?? base, Double(minutes))
        }
        return (moment, needsNumber ? number : nil)
    }

    private var isInFuture: Bool {
        resolved().completedAt > Date.now.addingTimeInterval(60)
    }

    private var canSave: Bool {
        if needsNumber && number == nil { return false }
        return !isInFuture
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isTimeTarget {
                        if periodDays > 1 {
                            DatePicker("Day", selection: $day, in: dayRange, displayedComponents: .date)
                        }
                        DatePicker("Time", selection: $timeOfDay, displayedComponents: .hourAndMinute)
                    } else {
                        DatePicker(
                            "When",
                            selection: $moment,
                            in: momentRange,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        if needsNumber {
                            HStack {
                                TextField("Value", text: $valueText)
                                    .keyboardType(.decimalPad)
                                Text(unitLabel)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    if isInFuture {
                        Text("That time hasn't happened yet.")
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add log" : "Edit log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let result = resolved()
        if let editing {
            editing.completedAt = result.completedAt
            editing.value = result.value
        } else {
            target.record(value: result.value, at: result.completedAt, in: modelContext)
        }
        try? modelContext.save()
        dismiss()
    }
}
