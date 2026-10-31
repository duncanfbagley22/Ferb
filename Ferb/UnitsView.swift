import SwiftUI
import SwiftData

/// Rename the units you added, and delete ones no item uses. Built-in units aren't listed:
/// they can't be changed. A unit that an item uses can't be deleted either (archived items
/// count), so nothing is ever left without its unit.
struct UnitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomUnit.name) private var units: [CustomUnit]

    @State private var renaming: CustomUnit?
    @State private var newName = ""
    @State private var message: String?

    var body: some View {
        Group {
            if units.isEmpty {
                ContentUnavailableView(
                    "No custom units",
                    systemImage: "ruler",
                    description: Text("Choose New unit… in the Unit menu when you set up an amount item.")
                )
            } else {
                List {
                    Section {
                        ForEach(units) { unit in
                            row(for: unit)
                        }
                    } footer: {
                        Text("Tap a unit to rename it everywhere it's used. Swipe to delete one that no item uses.")
                    }
                }
            }
        }
        .alert(
            "Rename unit",
            isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )
        ) {
            TextField("Name", text: $newName)
            Button("Save") { saveRename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert(
            message ?? "",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("OK", role: .cancel) { message = nil }
        }
        .navigationTitle("Units")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for unit: CustomUnit) -> some View {
        let count = unit.items.count
        return VStack(alignment: .leading, spacing: 2) {
            Text(unit.name)
            Text(count == 0 ? "Not used" : "\(count) item\(count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            newName = unit.name
            renaming = unit
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                delete(unit)
            }
        }
    }

    private func saveRename() {
        guard let unit = renaming else { return }
        renaming = nil
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != unit.name else { return }

        let matchesBuiltIn = QuantityUnit.allCases.contains {
            $0.title.caseInsensitiveCompare(name) == .orderedSame
        }
        let matchesOther = units.contains {
            $0 !== unit && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        if matchesBuiltIn || matchesOther {
            message = "There's already a unit called \(name)."
            return
        }
        unit.name = name
        try? modelContext.save()
    }

    private func delete(_ unit: CustomUnit) {
        let count = unit.items.count
        if count > 0 {
            message = "\(count) item\(count == 1 ? " uses" : "s use") this unit, including archived ones. Change \(count == 1 ? "its" : "their") unit first."
            return
        }
        modelContext.delete(unit)
        try? modelContext.save()
    }
}
