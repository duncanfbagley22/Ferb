import SwiftUI
import SwiftData

/// What the unit menu can select: a built-in unit or one you added.
private enum UnitChoice: Hashable {
    case builtIn(QuantityUnit)
    case custom(CustomUnit)
}

/// Creates a new item, or edits an existing one when opened with `init(editing:)`.
struct AddItemView: View {
    /// The area this item belongs to; only its subareas are offered.
    let area: Area
    /// Called with the new item right after it's saved (create mode only).
    let onCreated: ((Item) -> Void)?
    /// The item being edited, or nil when creating.
    let editing: Item?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subarea.sortOrder) private var allSubareas: [Subarea]
    @Query(sort: \CustomUnit.name) private var customUnits: [CustomUnit]

    @State private var name = ""
    @State private var chosenSubarea: Subarea?
    @State private var showingNewSubarea = false
    @State private var newSubareaName = ""
    @State private var isQuantity = false
    @State private var binarySubtype: BinarySubtype = .didIt
    @State private var quantitySubtype: QuantitySubtype = .amount
    @State private var quantityDirection: QuantityDirection = .target
    @State private var unitChoice: UnitChoice = .builtIn(.steps)
    @State private var showingNewUnit = false
    @State private var newUnitName = ""
    @State private var method: TrackingMethod = .check
    @State private var isPriority = false
    @State private var showingMeasurementWarning = false

    /// Create mode.
    init(area: Area, onCreated: ((Item) -> Void)? = nil) {
        self.area = area
        self.onCreated = onCreated
        self.editing = nil
    }

    /// Edit mode: opens pre-filled with the item's current values.
    init(editing item: Item) {
        self.area = item.area ?? .surface
        self.onCreated = nil
        self.editing = item
        _name = State(initialValue: item.name)
        _chosenSubarea = State(initialValue: item.subarea)
        _isQuantity = State(initialValue: item.trackingType == .quantity)
        _binarySubtype = State(initialValue: item.binarySubtype ?? .didIt)
        _quantitySubtype = State(initialValue: item.quantitySubtype ?? .amount)
        _quantityDirection = State(initialValue: item.quantityDirection ?? .target)
        _unitChoice = State(initialValue: item.customUnit.map(UnitChoice.custom) ?? .builtIn(item.unit ?? .steps))
        _method = State(initialValue: item.effectiveMethod)
        _isPriority = State(initialValue: item.isPriority)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    /// Subareas offered for this area, in display order.
    private var subareaOptions: [Subarea] {
        allSubareas.filter { $0.area == area }
    }

    /// The picked subarea, or the area's first one until the user picks.
    private var subarea: Subarea? {
        chosenSubarea ?? subareaOptions.first
    }

    /// Logging methods that fit the chosen tracking type.
    private var methodOptions: [TrackingMethod] {
        TrackingMethod.options(
            for: isQuantity ? .quantity : .binary,
            quantitySubtype: isQuantity ? quantitySubtype : nil
        )
    }

    // MARK: - Values the form would save

    private var newTrackingType: TrackingType { isQuantity ? .quantity : .binary }
    private var newBinarySubtype: BinarySubtype? { isQuantity ? nil : binarySubtype }
    private var newQuantitySubtype: QuantitySubtype? { isQuantity ? quantitySubtype : nil }
    private var newDirection: QuantityDirection? {
        (isQuantity && quantitySubtype.supportsDirection) ? quantityDirection : nil
    }
    private var newUnit: QuantityUnit? {
        guard isQuantity, quantitySubtype == .amount, case .builtIn(let unit) = unitChoice else { return nil }
        return unit
    }
    private var newCustomUnit: CustomUnit? {
        guard isQuantity, quantitySubtype == .amount, case .custom(let unit) = unitChoice else { return nil }
        return unit
    }
    private var unitChoiceTitle: String {
        switch unitChoice {
        case .builtIn(let unit): unit.title
        case .custom(let unit): unit.name
        }
    }
    private var newMethod: TrackingMethod {
        methodOptions.contains(method) ? method : methodOptions[0]
    }

    /// True when the edit changes how the item is measured (not just its name, subarea,
    /// priority or logging method).
    private func measurementChanged(for item: Item) -> Bool {
        item.trackingType != newTrackingType
            || item.binarySubtype != newBinarySubtype
            || item.quantitySubtype != newQuantitySubtype
            || item.quantityDirection != newDirection
            || item.unit != newUnit
            || item.customUnit != newCustomUnit
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)

                LabeledContent("Area", value: "\(area.letter) · \(area.title)")

                LabeledContent("Subarea") {
                    Menu {
                        Picker("Subarea", selection: Binding(get: { subarea }, set: { chosenSubarea = $0 })) {
                            ForEach(subareaOptions) { option in
                                Text(option.title).tag(Optional(option))
                            }
                        }
                        Divider()
                        Button("New subarea…", systemImage: "plus") {
                            newSubareaName = ""
                            showingNewSubarea = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(subarea?.title ?? "Select")
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                        }
                    }
                }

                if editing != nil {
                    Toggle("Priority", isOn: $isPriority)
                }

                Toggle(isQuantity ? "Quantity" : "Binary", isOn: $isQuantity)

                if isQuantity {
                    Picker("Type", selection: $quantitySubtype) {
                        ForEach(QuantitySubtype.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if quantitySubtype.supportsDirection {
                        Picker("Direction", selection: $quantityDirection) {
                            ForEach(QuantityDirection.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if quantitySubtype == .amount {
                        LabeledContent("Unit") {
                            Menu {
                                Picker("Unit", selection: $unitChoice) {
                                    ForEach(QuantityUnit.allCases) { option in
                                        Text(option.title).tag(UnitChoice.builtIn(option))
                                    }
                                    ForEach(customUnits) { custom in
                                        Text(custom.name).tag(UnitChoice.custom(custom))
                                    }
                                }
                                Divider()
                                Button("New unit…", systemImage: "plus") {
                                    newUnitName = ""
                                    showingNewUnit = true
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(unitChoiceTitle)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                } else {
                    Picker("Type", selection: $binarySubtype) {
                        ForEach(BinarySubtype.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if methodOptions.count > 1 {
                    Picker("Log with", selection: $method) {
                        ForEach(methodOptions) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let editing {
                    Section {
                        Button("Archive item", systemImage: "archivebox") {
                            editing.isArchived = true
                            dismiss()
                        }
                    } footer: {
                        Text("Hides it and its targets from your lists. Restore any time from Settings → Archived.")
                    }
                }
            }
            .onChange(of: methodOptions) {
                if !methodOptions.contains(method) { method = methodOptions[0] }
            }
            .alert("New subarea", isPresented: $showingNewSubarea) {
                TextField("Name", text: $newSubareaName)
                Button("Add") { addSubarea() }
                Button("Cancel", role: .cancel) { newSubareaName = "" }
            } message: {
                Text("It will be added to \(area.title).")
            }
            .alert("New unit", isPresented: $showingNewUnit) {
                TextField("Name", text: $newUnitName)
                Button("Add") { addUnit() }
                Button("Cancel", role: .cancel) { newUnitName = "" }
            } message: {
                Text("Any item can use it, for example pushups or glasses.")
            }
            .navigationTitle(editing == nil ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty || subarea == nil)
                }
            }
        }
        .alert("Change how it's measured?", isPresented: $showingMeasurementWarning) {
            Button("Change anyway", role: .destructive) {
                if let editing {
                    applyEdits(to: editing)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let targets = editing?.targets.count ?? 0
            let logs = editing?.targets.reduce(0) { $0 + $1.logs.count } ?? 0
            Text("This item has \(targets) target\(targets == 1 ? "" : "s") and \(logs) log\(logs == 1 ? "" : "s"). Changing how it's measured can make their numbers not line up.")
        }
    }

    /// Creates a custom subarea in this area and selects it. If one with the same name
    /// already exists in the area, selects that one instead of making a duplicate.
    private func addSubarea() {
        let title = newSubareaName.trimmingCharacters(in: .whitespaces)
        newSubareaName = ""
        guard !title.isEmpty else { return }

        if let existing = subareaOptions.first(where: {
            $0.title.caseInsensitiveCompare(title) == .orderedSame
        }) {
            chosenSubarea = existing
            return
        }

        let created = Subarea(
            key: UUID().uuidString,
            title: title,
            area: area,
            isBuiltIn: false,
            sortOrder: (allSubareas.map(\.sortOrder).max() ?? 0) + 1
        )
        modelContext.insert(created)
        chosenSubarea = created
    }

    /// Creates a custom unit and selects it. A name that matches a built-in or an existing
    /// custom unit (ignoring case) selects that one instead of making a duplicate.
    private func addUnit() {
        let name = newUnitName.trimmingCharacters(in: .whitespaces)
        newUnitName = ""
        guard !name.isEmpty else { return }

        if let builtIn = QuantityUnit.allCases.first(where: {
            $0.title.caseInsensitiveCompare(name) == .orderedSame
        }) {
            unitChoice = .builtIn(builtIn)
            return
        }
        if let existing = customUnits.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            unitChoice = .custom(existing)
            return
        }

        let created = CustomUnit(name: name)
        modelContext.insert(created)
        unitChoice = .custom(created)
    }

    private func save() {
        if let editing {
            // Name, subarea, priority and logging method are safe to change freely. Changing
            // how it's measured asks first if the item already has targets.
            if measurementChanged(for: editing) && !editing.targets.isEmpty {
                showingMeasurementWarning = true
            } else {
                applyEdits(to: editing)
                dismiss()
            }
            return
        }

        guard let subarea else { return }
        let item = Item(
            name: trimmedName,
            subarea: subarea,
            trackingType: newTrackingType,
            binarySubtype: newBinarySubtype,
            quantitySubtype: newQuantitySubtype,
            quantityDirection: newDirection,
            unit: newUnit,
            customUnit: newCustomUnit,
            method: newMethod
        )
        modelContext.insert(item)
        // Save now so the item is settled before the New target form opens with it selected.
        try? modelContext.save()
        onCreated?(item)
        dismiss()
    }

    private func applyEdits(to item: Item) {
        item.name = trimmedName
        if let subarea { item.subarea = subarea }
        item.isPriority = isPriority
        item.trackingType = newTrackingType
        item.binarySubtype = newBinarySubtype
        item.quantitySubtype = newQuantitySubtype
        item.quantityDirection = newDirection
        item.unit = newUnit
        item.customUnit = newCustomUnit
        item.method = newMethod
    }
}
