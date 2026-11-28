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
    @State private var showFromEnabled = false
    @State private var showFromTime = AddTargetView.date(fromMinutes: 21 * 60)
    @State private var isRolling = false
    @State private var badgeNudge = false
    @State private var oncePerDay = false

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
            _showFromEnabled = State(initialValue: fields.showFromEnabled)
            _showFromTime = State(initialValue: fields.showFromTime)
            _isRolling = State(initialValue: fields.isRolling)
            _badgeNudge = State(initialValue: fields.badgeNudge)
            _oncePerDay = State(initialValue: fields.oncePerDay)
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
        _showFromEnabled = State(initialValue: fields.showFromEnabled)
        _showFromTime = State(initialValue: fields.showFromTime)
        _isRolling = State(initialValue: fields.isRolling)
        _badgeNudge = State(initialValue: fields.badgeNudge)
        _oncePerDay = State(initialValue: fields.oncePerDay)
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
        var showFromEnabled: Bool
        var showFromTime: Date
        var isRolling: Bool
        var badgeNudge: Bool
        var oncePerDay: Bool
    }

    /// Starting tolerance (minutes) for new time targets, so "on time" isn't one exact minute.
    private static let defaultTimeTolerance = "30"

    /// Today at the given minutes since midnight (only the clock part is used).
    @MainActor
    private static func date(fromMinutes minutes: Int) -> Date {
        let parts = DateComponents(hour: (minutes / 60) % 24, minute: minutes % 60)
        return Calendar.current.date(from: parts) ?? .now
    }

    /// Minutes since midnight for the clock part of a date.
    @MainActor
    private static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

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
            timeOfDay: timeOfDay,
            showFromEnabled: target.showFromMinutes != nil,
            showFromTime: date(fromMinutes: target.showFromMinutes ?? 21 * 60),
            isRolling: target.isRolling == true,
            badgeNudge: target.badgeNudge == true,
            oncePerDay: target.oncePerDay == true
        )
    }

    /// Editing a target that already has logs: frequency and goal are locked.
    private var isLocked: Bool {
        guard let editing else { return false }
        return !editing.logs.isEmpty
    }

    /// Rolling only applies to a multi-day cadence on a non-time target; otherwise it's the fixed default.
    private var usesRolling: Bool {
        isRolling && everyDays > 1 && quantitySubtype != .timeTarget
    }

    /// "Count each day once" only fits an amount in Times (not a cap) over more than one day.
    private var offersOncePerDay: Bool {
        guard everyDays > 1, let item = selectedItem, item.trackingType == .quantity,
              item.quantitySubtype == .amount, item.quantityDirection != .cap,
              item.unit == .times, item.customUnit == nil else { return false }
        return true
    }

    private var usesOncePerDay: Bool { oncePerDay && offersOncePerDay }

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

                    if everyDays > 1 && quantitySubtype != .timeTarget {
                        Picker("Window", selection: $isRolling) {
                            Text("Fixed").tag(false)
                            Text("Rolling").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .disabled(isLocked)
                        Text(isRolling
                            ? "Every day looks back over the last \(everyDays) days, so any \(everyDays)-day stretch can meet the goal."
                            : "Back-to-back \(everyDays)-day blocks from the start date; each block is judged on its own.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if offersOncePerDay {
                        Toggle("Count each day once", isOn: $oncePerDay)
                        Text(oncePerDay
                            ? "Extra logs on the same day are kept but count once, so the goal needs that many different days."
                            : "Every log counts, so several in one day can add up.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if oncePerDay, let goal = number(from: valueText), goal > Double(everyDays) {
                            Text("The goal is higher than the number of days, so it can never be met.")
                                .font(.caption)
                                .foregroundStyle(Color.goalMissed)
                        }
                    }

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

                Section {
                    Toggle("Only show from a set time", isOn: $showFromEnabled)
                    if showFromEnabled {
                        DatePicker("Show from", selection: $showFromTime, displayedComponents: .hourAndMinute)
                    }
                    Toggle("Badge until done", isOn: $badgeNudge)
                } header: {
                    Text("Quick update")
                } footer: {
                    Text("Until this time each day, the target stays out of Quick update and shows blue on Home, like Later today. Doesn't affect past results. \"Badge until done\" counts the target on the app icon's red badge each day until you log it, skip it or set it aside.")
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
        target.showFromMinutes = showFromEnabled ? Self.minutes(from: showFromTime) : nil
        target.isRolling = usesRolling ? true : nil
        target.badgeNudge = badgeNudge ? true : nil
        target.oncePerDay = usesOncePerDay ? true : nil
        modelContext.insert(target)
        onSaved?()
        dismiss()
    }

    private func saveEdits(to target: Target) {
        // The end of the window can always move (never to before the last logged day).
        target.durationDays = isOngoing ? nil : max(durationDays, minDuration)
        // The daily show-from time never changes past results, so it's editable even with history.
        target.showFromMinutes = showFromEnabled ? Self.minutes(from: showFromTime) : nil
        target.badgeNudge = badgeNudge ? true : nil
        // Counting each day once changes what's counted, never what's recorded, so it's editable with history.
        target.oncePerDay = usesOncePerDay ? true : nil

        // Frequency and goal only change while there's no history to re-judge.
        guard !isLocked else { return }
        target.intervalDays = everyDays
        target.isRolling = usesRolling ? true : nil
        target.value = value
        target.tolerance = quantitySubtype == nil ? nil : number(from: toleranceText)
        target.toleranceMode = quantitySubtype == .timeTarget ? .absolute : toleranceMode
        target.timeDirection = quantitySubtype == .timeTarget ? timeDirection : .either
    }
}
