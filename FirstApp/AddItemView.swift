import SwiftUI
import SwiftData

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

    @State private var name = ""
    @State private var chosenSubarea: Subarea?
    @State private var showingNewSubarea = false
    @State private var newSubareaName = ""
    @State private var isQuantity = false
    @State private var binarySubtype: BinarySubtype = .didIt
    @State private var quantitySubtype: QuantitySubtype = .amount
    @State private var quantityDirection: QuantityDirection = .target
    @State private var unit: QuantityUnit = .steps
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
        _unit = State(initialValue: item.unit ?? .steps)
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
        (isQuantity && quantitySubtype == .amount) ? unit : nil
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
                        Picker("Unit", selection: $unit) {
                            ForEach(QuantityUnit.allCases) { option in
                                Text(option.title).tag(option)
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
            method: newMethod
        )
        modelContext.insert(item)
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
        item.method = newMethod
    }
}
