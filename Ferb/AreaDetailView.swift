import SwiftUI
import SwiftData

/// One area's page: its active targets as cards, then any items without a target.
struct AreaDetailView: View {
    let area: Area
    @Query(sort: \Target.startDate) private var allTargets: [Target]
    @Query(sort: \Item.name) private var allItems: [Item]

    private var targets: [Target] {
        allTargets.active(in: area)
    }

    private var areaItems: [Item] {
        allItems.filter { $0.area == area && !$0.isArchived }
    }

    /// Items with no active target; the ones with one already show up as target cards.
    private var items: [Item] {
        areaItems
            .filter { item in !item.targets.contains { $0.isActive() } }
            .sorted { ($0.isPriority ? 0 : 1, $0.name) < ($1.isPriority ? 0 : 1, $1.name) }
    }

    var body: some View {
        ScrollView(.vertical) {
            AreaListPage(area: area, targets: targets, items: items)
        }
    }
}

private struct AreaListPage: View {
    let area: Area
    let targets: [Target]
    let items: [Item]

    @Environment(\.modelContext) private var modelContext
    @State private var itemToDelete: Item?
    @State private var targetToLog: Target?
    /// Whether count targets on this page show their usual history row (true) or this period's time
    /// dots (false). Remembered per area.
    @AppStorage private var showCountHistory: Bool

    init(area: Area, targets: [Target], items: [Item]) {
        self.area = area
        self.targets = targets
        self.items = items
        _showCountHistory = AppStorage(wrappedValue: false, "showCountHistory.\(String(describing: area))")
    }

    private let cardColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        // Not a List: row swipe actions don't work inside a ScrollView + LazyVStack,
        // so logging, archiving and deleting use context menus.
        LazyVStack(alignment: .leading, spacing: 0) {
            targetsHeader
            if targets.isEmpty {
                emptyRow("No active targets")
            } else {
                LazyVGrid(columns: cardColumns, spacing: 8) {
                    ForEach(targets) { target in
                        targetLink(for: target)
                            .contextMenu {
                                // Binary targets are one tap; the rest need a value, so they open Log now.
                                if target.item?.trackingType == .binary {
                                    Button("Mark done", systemImage: "checkmark") {
                                        target.record(in: modelContext)
                                    }
                                } else {
                                    Button("Log now…", systemImage: "plus.circle") {
                                        targetToLog = target
                                    }
                                }
                                Button("Archive target", systemImage: "archivebox") {
                                    target.isArchived = true
                                }
                                if let item = target.item {
                                    Button("Archive item", systemImage: "archivebox") {
                                        item.isArchived = true
                                    }
                                }
                                Button(role: .destructive) {
                                    modelContext.delete(target)
                                } label: {
                                    Label("Delete target", systemImage: "trash")
                                }
                                if let item = target.item {
                                    Button(role: .destructive) {
                                        itemToDelete = item
                                    } label: {
                                        Label("Delete item", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }

            if !items.isEmpty {
                sectionHeader("\(items.count) \(items.count == 1 ? "item" : "items") without a target")
                LazyVGrid(columns: cardColumns, spacing: 8) {
                    ForEach(items) { item in
                        ItemGridCard(item: item)
                            .contextMenu {
                                Button("Archive", systemImage: "archivebox") {
                                    item.isArchived = true
                                }
                                Button(role: .destructive) {
                                    itemToDelete = item
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .alert(
            "Delete item?",
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            ),
            presenting: itemToDelete
        ) { item in
            Button("Delete", role: .destructive) {
                modelContext.delete(item)
                itemToDelete = nil
            }
            Button("Cancel", role: .cancel) { itemToDelete = nil }
        } message: { item in
            Text("This also deletes its \(item.targets.count) target(s) and all of their logs.")
        }
        .sheet(item: $targetToLog) { target in
            LogNowView(target: target)
        }
    }

    /// A target card that opens its item's page; plain card if the target has no item.
    @ViewBuilder
    private func targetLink(for target: Target) -> some View {
        if let item = target.item {
            NavigationLink(value: TargetPagerRoute(area: area, startItem: item)) {
                TargetGridCard(target: target, showHistory: showCountHistory)
            }
            .buttonStyle(.plain)
        } else {
            TargetGridCard(target: target, showHistory: showCountHistory)
        }
    }

    private var hasCountTargets: Bool {
        targets.contains { $0.timesGoal != nil }
    }

    /// The "N targets" header, with a Count / History switch on the right when the page has a count
    /// target (like "3 times a week"): Count shows this period's time dots, History the past periods.
    private var targetsHeader: some View {
        HStack {
            Text("\(targets.count) \(targets.count == 1 ? "target" : "targets")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if hasCountTargets {
                Picker("Count targets show", selection: $showCountHistory) {
                    Text("Count").tag(false)
                    Text("History").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .areaRow()
    }
}

private extension View {
    /// List-style row: padding, full width, and a divider underneath.
    func areaRow() -> some View {
        VStack(spacing: 0) {
            self
                .padding(.vertical, 10)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            Divider()
                .padding(.leading)
        }
    }
}
