import SwiftUI
import SwiftData

/// Creates a target, or edits one when opened with `init(editing:)`. Editing rules:
/// the end of the window can always change; frequency and goal can only change while the
/// target has no logs (otherwise past periods would be re-judged), and the start date
/// stays fixed. A target with history offers "start a new target from this one" instead.
struct AddTargetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Item> { $0.isArchived == false }, sort: \Item.name) private var items: [Item]
    /// When set, only this area's items are offered in the picker.
    let limitToArea: Area?
    /// The target being edited, or nil when creating.
    let editing: Target?
    /// Called after a target is saved.
    let onSaved: (() -> Void)?

    @State private var selectedItem: Item?
    @State private var everyDays = 1
    @State private var startDate = Date.now
    @State private var isOngoing = true
    @State private var durationDays = 14
    @State private var valueText = ""
    @State private var toleranceText = ""
    @State private var toleranceMode: ToleranceMode = .absolute
    @State private var timeOfDay = Date.now
    @State private var timeDirection: TimeDirection = .either
    @State private var showingNewFromThis = false

    /// Create mode. Pass `basedOn` to pre-fill the form from an existing target (starting today).
    init(
        item: Item? = nil,
        limitToArea: Area? = nil,
        basedOn source: Target? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self.limitToArea = limitToArea
        self.editing = nil
        self.onSaved = onSaved
        _selectedItem = State(initialValue: item ?? source?.item)
        if source == nil, item?.trackingType == .quantity, item?.quantitySubtype == .timeTarget {
            _toleranceText = State(initialValue: Self.defaultTimeTolerance)
        }
        if let source {
            let fields = Self.fields(from: source)
            _everyDays = State(initialValue: fields.everyDays)
            _isOngoing = State(initialValue: fields.isOngoing)
            _durationDays = State(initialValue: fields.durationDays)
            _valueText = State(initialValue: fields.valueText)
            _toleranceText = State(initialValue: fields.toleranceText)
            _toleranceMode = State(initialValue: fields.toleranceMode)
            _timeOfDay = State(initialValue: fields.timeOfDay)
            _timeDirection = State(initialValue: fields.timeDirection)
        }
    }

    /// Edit mode: opens pre-filled with the target's current values.
    init(editing target: Target) {
        self.limitToArea = nil
        self.editing = target
        self.onSaved = nil
        let fields = Self.fields(from: target)
        _selectedItem = State(initialValue: target.item)
        _everyDays = State(initialValue: fields.everyDays)
        _startDate = State(initialValue: target.startDate)
        _isOngoing = State(initialValue: fields.isOngoing)
        _durationDays = State(initialValue: fields.durationDays)
        _valueText = State(initialValue: fields.valueText)
        _toleranceText = State(initialValue: fields.toleranceText)
        _toleranceMode = State(initialValue: fields.toleranceMode)
        _timeOfDay = State(initialValue: fields.timeOfDay)
        _timeDirection = State(initialValue: fields.timeDirection)
    }

    private struct Fields {
        var everyDays: Int
        var isOngoing: Bool
        var durationDays: Int
        var valueText: String
        var toleranceText: String
        var toleranceMode: ToleranceMode
        var timeDirection: TimeDirection
        var timeOfDay: Date
    }

    /// Starting tolerance (minutes) for new time targets, so "on time" isn't one exact minute.
    private static let defaultTimeTolerance = "30"

    @MainActor
    private static func plainNumber(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(number)
    }

    @MainActor
    private static func fields(from target: Target) -> Fields {
        let isTime = target.item?.quantitySubtype == .timeTarget
        var timeOfDay = Date.now
        var valueText = ""
        if let value = target.value {
            if isTime {
                let parts = DateComponents(hour: (Int(value) / 60) % 24, minute: Int(value) % 60)
                timeOfDay = Calendar.current.date(from: parts) ?? .now
            } else {
                valueText = plainNumber(value)
            }
        }
        return Fields(
            everyDays: target.intervalDays,
            isOngoing: target.durationDays == nil,
            durationDays: target.durationDays ?? 14,
            valueText: valueText,
            toleranceText: target.tolerance.map(plainNumber) ?? "",
            toleranceMode: target.toleranceMode,
            timeDirection: target.timeDirection,
            timeOfDay: timeOfDay
        )
    }

    /// Editing a target that already has logs: frequency and goal are locked.
    private var isLocked: Bool {
        guard let editing else { return false }
        return !editing.logs.isEmpty
    }

    /// Shortest window that still covers every logged day.
    private var minDuration: Int {
        guard let editing, let last = editing.lastCompletedAt else { return 1 }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: editing.startDate),
            to: calendar.startOfDay(for: last)
        ).day ?? 0
        return max(1, days + 1)
    }

    private var lastDayText: String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let last = calendar.date(byAdding: .day, value: max(durationDays, 1) - 1, to: start) ?? start
        return last.formatted(date: .abbreviated, time: .omitted)
    }

    /// Only set when the selected item is a quantity item.
    private var quantitySubtype: QuantitySubtype? {
        guard let item = selectedItem, item.trackingType == .quantity else { return nil }
        return item.quantitySubtype
    }

    private func number(from text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// Amount/duration: the typed number. Time target: minutes since midnight.
    private var value: Double? {
        switch quantitySubtype {
        case .amount?, .duration?:
            return number(from: valueText)
        case .timeTarget?:
            let parts = Calendar.current.dateComponents([.hour, .minute], from: timeOfDay)
            return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        case nil:
            return nil
        }
    }

    private var valueUnitLabel: String {
        switch quantitySubtype {
        case .amount?: selectedItem?.unitName ?? ""
        case .duration?: "minutes"
        default: ""
        }
    }

    private var toleranceUnitLabel: String {
        switch quantitySubtype {
        case .amount?: valueUnitLabel
        default: "minutes"
        }
    }

    private var timeToleranceCaption: String {
        switch timeDirection {
        case .either:
            "Minutes either side of the time that still count as on time. Leave blank to require the exact minute."
        case .noLaterThan:
            "Anything earlier counts. Minutes past the time that still count. Leave blank to allow none."
        case .noEarlierThan:
            "Anything later counts. Minutes before the time that still count. Leave blank to allow none."
        }
    }

    private var canSave: Bool {
        guard selectedItem != nil else { return false }
        return quantitySubtype == nil || value != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let editing {
                        LabeledContent("Item", value: editing.item?.name ?? "Unknown item")
                    } else if items.isEmpty {
                        Text("Create an item first: open an area from Home and tap +.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Item", selection: $selectedItem) {
                            Text("Select…").tag(nil as Item?)
                            ForEach(Area.allCases.filter { limitToArea == nil || $0 == limitToArea }) { area in
                                let areaItems = items.filter { $0.area == area }
                                if !areaItems.isEmpty {
                                    Section("\(area.letter) · \(area.title)") {
                                        ForEach(areaItems) { item in
                                            Text(item.name).tag(Optional(item))
                                        }
                                    }
                                }
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }

                    if let item = selectedItem {
                        LabeledContent("Measured as", value: item.typeSummary)
                    }
                }

                Section("Schedule") {
                    Stepper(
                        "Every \(everyDays) day\(everyDays == 1 ? "" : "s")",
                        value: $everyDays,
                        in: 1...365
                    )
                    .disabled(isLocked)

                    if editing == nil {
                        DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    } else {
                        LabeledContent("Starts", value: startDate.formatted(date: .abbreviated, time: .omitted))
                    }

                    Toggle("Ongoing", isOn: $isOngoing)
                    if !isOngoing {
                        Stepper(
                            "For \(durationDays) day\(durationDays == 1 ? "" : "s")",
                            value: $durationDays,
                            in: minDuration...365
                        )
                        if editing != nil {
                            LabeledContent("Last day", value: lastDayText)
                        }
                    }
                }

                if let subtype = quantitySubtype {
                    Section("Goal") {
                        if subtype == .timeTarget {
                            DatePicker("Time", selection: $timeOfDay, displayedComponents: .hourAndMinute)
                            Picker("On time means", selection: $timeDirection) {
                                ForEach(TimeDirection.allCases) { direction in
                                    Text(direction.title).tag(direction)
                                }
                            }
                        } else {
                            HStack {
                                TextField("Value", text: $valueText)
                                    .keyboardType(.decimalPad)
                                Text(valueUnitLabel)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            TextField("Tolerance (optional)", text: $toleranceText)
                                .keyboardType(.decimalPad)
                            Text(toleranceMode == .percent ? "%" : toleranceUnitLabel)
                                .foregroundStyle(.secondary)
                        }
                        if subtype == .timeTarget {
                            Text(timeToleranceCaption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if subtype != .timeTarget {
                            Picker("Tolerance type", selection: $toleranceMode) {
                                ForEach(ToleranceMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .disabled(isLocked)
                }

                if isLocked {
                    Section {
                        Button("Start a new target from this one", systemImage: "arrow.triangle.2.circlepath") {
                            showingNewFromThis = true
                        }
                    } footer: {
                        Text("This target has history, so its frequency and goal are locked to keep past results accurate. You can still change when it ends. To change the rest, start a new target; this one ends the day before it begins.")
                    }
                }
            }
            .onChange(of: selectedItem) {
                guard editing == nil else { return }
                valueText = ""
                toleranceText = ""
                toleranceMode = .absolute
                timeDirection = .either
                if selectedItem?.trackingType == .quantity, selectedItem?.quantitySubtype == .timeTarget {
                    toleranceText = Self.defaultTimeTolerance
                }
            }
            .onChange(of: isOngoing) {
                if !isOngoing { durationDays = max(durationDays, minDuration) }
            }
            .navigationTitle(editing == nil ? "New Target" : "Edit Target")
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
            .sheet(isPresented: $showingNewFromThis) {
                AddTargetView(item: editing?.item, basedOn: editing, onSaved: { dismiss() })
            }
        }
    }

    private func save() {
        if let editing {
            saveEdits(to: editing)
            onSaved?()
            dismiss()
            return
        }
        guard let item = selectedItem else { return }

        // A new target replaces the item's earlier ones: end any that are still
        // running as of the new start date so they stop on the day before it.
        let calendar = Calendar.current
        let newStart = calendar.startOfDay(for: startDate)
        for old in item.targets where old.startDate < newStart {
            if let end = old.endDate(), end <= newStart { continue }
            old.durationDays = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: old.startDate),
                to: newStart
            ).day ?? 0
        }

        let target = Target(
            item: item,
            startDate: startDate,
            durationDays: isOngoing ? nil : durationDays,
            intervalDays: everyDays,
            value: value,
            tolerance: quantitySubtype == nil ? nil : number(from: toleranceText),
            toleranceMode: quantitySubtype == .timeTarget ? .absolute : toleranceMode,
            timeDirection: quantitySubtype == .timeTarget ? timeDirection : .either
        )
        modelContext.insert(target)
        onSaved?()
        dismiss()
    }

    private func saveEdits(to target: Target) {
        // The end of the window can always move (never to before the last logged day).
        target.durationDays = isOngoing ? nil : max(durationDays, minDuration)

        // Frequency and goal only change while there's no history to re-judge.
        guard !isLocked else { return }
        target.intervalDays = everyDays
        target.value = value
        target.tolerance = quantitySubtype == nil ? nil : number(from: toleranceText)
        target.toleranceMode = quantitySubtype == .timeTarget ? .absolute : toleranceMode
        target.timeDirection = quantitySubtype == .timeTarget ? timeDirection : .either
    }
}
