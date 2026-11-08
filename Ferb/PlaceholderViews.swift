import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage(HomeSettings.capHeldMinutesKey) private var capHeldMinutes = HomeSettings.defaultCapHeldMinutes
    @Environment(\.modelContext) private var modelContext

    /// Called just before data is deleted, so screens holding a deleted item or target can be closed.
    var resetNavigation: () -> Void

    @State private var showingDeleteAlert = false
    @State private var confirmText = ""
    @State private var deleteMessage: String?

    init(resetNavigation: @escaping () -> Void = {}) {
        self.resetNavigation = resetNavigation
    }

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
                    DatePicker("Caps count as held at", selection: capHeldTime, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Home")
                } footer: {
                    Text("On the Home cards, a cap that is still under its limit turns dark green at this time on the last day of its period.")
                }

                Section {
                NavigationLink {
                    AlertsView()
                } label: {
                    Label("Alerts", systemImage: "bell")
                }
                NavigationLink {
                    NotesView()
                } label: {
                    Label("Notes", systemImage: "note.text")
                }
                NavigationLink {
                    SubareasView()
                } label: {
                    Label("Subareas", systemImage: "square.grid.2x2")
                }
                NavigationLink {
                    UnitsView()
                } label: {
                    Label("Units", systemImage: "ruler")
                }
                NavigationLink {
                    ArchivedView()
                } label: {
                    Label("Archived", systemImage: "archivebox")
                }
                }

                Section {
                    Button("Delete all data…", role: .destructive) {
                        confirmText = ""
                        showingDeleteAlert = true
                    }
                } footer: {
                    Text("Permanently removes all items, targets, logs, notes, units and plans, and resets alerts and subareas. There is no backup, so this can't be undone.")
                }
            }
            .navigationTitle("Settings")
            .alert("Delete all data?", isPresented: $showingDeleteAlert) {
                TextField("Type DELETE", text: $confirmText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Delete everything", role: .destructive) {
                    if confirmText.trimmingCharacters(in: .whitespaces) == "DELETE" {
                        deleteAllData()
                    } else {
                        deleteMessage = "Nothing was deleted. You need to type DELETE exactly."
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently erases everything in the app. Type DELETE to confirm.")
            }
            .alert(
                deleteMessage ?? "",
                isPresented: Binding(
                    get: { deleteMessage != nil },
                    set: { if !$0 { deleteMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { deleteMessage = nil }
            }
        }
    }

    /// The cap-held time as a `Date` for the time picker; stored as minutes since midnight.
    private var capHeldTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: capHeldMinutes / 60, minute: capHeldMinutes % 60, second: 0, of: .now
                ) ?? .now
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                capHeldMinutes = (parts.hour ?? 22) * 60 + (parts.minute ?? 0)
            }
        )
    }

    /// Erases every record, then restores the built-in subareas and default alerts.
    /// Children go first so each delete rule is honored. Appearance (light/dark) is kept.
    private func deleteAllData() {
        resetNavigation()
        do {
            try deleteAll(Log.self)
            try deleteAll(Target.self)
            try deleteAll(Item.self)
            try deleteAll(Subarea.self)
            try deleteAll(Note.self)
            try deleteAll(Reminder.self)
            try deleteAll(CustomUnit.self)
            try deleteAll(PlanEntry.self)
            try modelContext.save()
        } catch {
            deleteMessage = "Couldn't delete everything: \(error.localizedDescription)"
        }
        // Put back what the app expects to always exist (this normally only runs at launch).
        Subarea.seedDefaults(in: modelContext)
        Reminder.seedDefaults(in: modelContext)
        Task { await ReminderScheduler.refresh(in: modelContext, requestingPermission: false) }
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        for object in try modelContext.fetch(FetchDescriptor<T>()) {
            modelContext.delete(object)
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
