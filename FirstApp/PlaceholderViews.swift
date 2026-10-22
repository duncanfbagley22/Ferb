import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                NavigationLink {
                    SubareasView()
                } label: {
                    Label("Subareas", systemImage: "square.grid.2x2")
                }
                NavigationLink {
                    ArchivedView()
                } label: {
                    Label("Archived", systemImage: "archivebox")
                }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

/// Rename any subarea, and delete custom ones that no item uses. Built-in subareas can't be
/// deleted (the app restores any that go missing), and one that items use can't either, so
/// nothing is ever left without a subarea.
struct SubareasView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Subarea.sortOrder) private var subareas: [Subarea]

    @State private var renaming: Subarea?
    @State private var newName = ""
    @State private var message: String?

    var body: some View {
        Group {
            List {
                ForEach(Area.allCases) { area in
                    Section("\(area.letter) · \(area.title)") {
                        ForEach(subareas.filter { $0.area == area }) { subarea in
                            row(for: subarea)
                        }
                    }
                }
            }
            .alert(
                "Rename subarea",
                isPresented: Binding(
                    get: { renaming != nil },
                    set: { if !$0 { renaming = nil } }
                )
            ) {
                TextField("Name", text: $newName)
                Button("Save") { saveRename() }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
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
        .navigationTitle("Subareas")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for subarea: Subarea) -> some View {
        let count = subarea.items.count
        return VStack(alignment: .leading, spacing: 2) {
            Text(subarea.title)
            Text("\(subarea.isBuiltIn ? "Built in" : "Custom") · \(count == 0 ? "not used" : "\(count) item\(count == 1 ? "" : "s")")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            newName = subarea.title
            renaming = subarea
        }
        .swipeActions(edge: .trailing) {
            if !subarea.isBuiltIn {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    delete(subarea)
                }
            }
        }
    }

    private func saveRename() {
        guard let subarea = renaming else { return }
        renaming = nil
        let title = newName.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, title != subarea.title else { return }

        let taken = subareas.contains {
            $0 !== subarea && $0.area == subarea.area
                && $0.title.caseInsensitiveCompare(title) == .orderedSame
        }
        if taken {
            message = "\(subarea.area.title) already has a subarea called \(title)."
            return
        }
        subarea.title = title
        try? modelContext.save()
    }

    private func delete(_ subarea: Subarea) {
        let count = subarea.items.count
        if count > 0 {
            message = "\(count) item\(count == 1 ? " uses" : "s use") this subarea, including archived ones. Move \(count == 1 ? "it" : "them") to another subarea first."
            return
        }
        modelContext.delete(subarea)
        try? modelContext.save()
    }
}

/// Archived items and targets, with a way to bring each back.
struct ArchivedView: View {
    @Query(filter: #Predicate<Item> { $0.isArchived == true }, sort: \Item.name)
    private var archivedItems: [Item]
    @Query(filter: #Predicate<Target> { $0.isArchived == true }, sort: \Target.startDate, order: .reverse)
    private var archivedTargets: [Target]

    /// Targets archived on their own. Ones under an archived item come back with the item.
    private var looseTargets: [Target] {
        archivedTargets.filter { $0.item?.isArchived != true }
    }

    var body: some View {
        Group {
            if archivedItems.isEmpty && looseTargets.isEmpty {
                ContentUnavailableView(
                    "Nothing archived",
                    systemImage: "archivebox",
                    description: Text("Archived items and targets show up here so you can restore them.")
                )
            } else {
                List {
                    if !archivedItems.isEmpty {
                        Section("Items") {
                            ForEach(archivedItems) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                        Text("\(item.subarea?.title ?? "No subarea") · \(item.targets.count) target\(item.targets.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Restore") { item.isArchived = false }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    if !looseTargets.isEmpty {
                        Section("Targets") {
                            ForEach(looseTargets) { target in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(target.item?.name ?? "Unknown item")
                                        Text("\(target.cadenceTitle) · \(target.dateRangeText)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Restore") { target.isArchived = false }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Archived")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Generic stand-in for screens that aren't designed yet.
struct PlaceholderSheet: View {
    let title: String
    let message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text(message)
                .foregroundStyle(.secondary)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
