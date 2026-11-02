import SwiftUI
import SwiftData

/// An item's page: its current target, a strip of previous targets, and buttons for
/// starting a new target or editing the item.
struct ItemSummaryView: View {
    let item: Item
    /// False when the page sits inside `TargetPagerView`, which sets the title for the selected page.
    var showsTitle = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingNewTarget = false
    @State private var showingSettings = false
    @State private var targetToDelete: Target?

    private var currentTarget: Target? {
        item.targets.filter { $0.isActive() }.max { $0.startDate < $1.startDate }
    }

    /// Targets that have already ended, newest first. Upcoming targets are not shown yet.
    private var previousTargets: [Target] {
        let today = Calendar.current.startOfDay(for: .now)
        return item.targets
            .filter { !$0.isArchived && !$0.isActive() && Calendar.current.startOfDay(for: $0.startDate) <= today }
            .sorted { $0.startDate > $1.startDate }
    }

    /// Targets that haven't started yet, soonest first.
    private var upcomingTargets: [Target] {
        let today = Calendar.current.startOfDay(for: .now)
        return item.targets
            .filter { !$0.isArchived && Calendar.current.startOfDay(for: $0.startDate) > today }
            .sorted { $0.startDate < $1.startDate }
    }

    /// A horizontal strip of target cards. Long-press one to archive or delete it.
    private func targetStrip(_ targets: [Target]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(targets) { target in
                    NavigationLink(value: target) {
                        TargetCard(target: target, color: .gray, showStatus: false)
                            .frame(width: 220)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Archive", systemImage: "archivebox") {
                            target.isArchived = true
                        }
                        Button(role: .destructive) {
                            targetToDelete = target
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("\(item.subarea?.title ?? "No subarea") · \(item.typeSummary)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Current target")
                        .font(.headline)
                    if let target = currentTarget {
                        NavigationLink(value: target) {
                            TargetCard(
                                target: target,
                                color: (target.status() as TargetStatus?).color,
                                showStatus: true
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("No active target")
                            .foregroundStyle(.secondary)
                    }
                }

                if !upcomingTargets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Upcoming targets")
                            .font(.headline)
                        targetStrip(upcomingTargets)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Previous targets")
                        .font(.headline)
                    if previousTargets.isEmpty {
                        Text("None yet")
                            .foregroundStyle(.secondary)
                    } else {
                        targetStrip(previousTargets)
                    }
                }
            }
            .padding()
        }
        .modifier(ItemPageTitle(title: item.name, isShown: showsTitle))
        .onChange(of: item.isArchived) { _, archived in
            // Archiving from Item settings: leave the page of an item that's now hidden.
            if archived { dismiss() }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button { showingSettings = true } label: {
                    Text("Edit item").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { showingNewTarget = true } label: {
                    Text("New target").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
        .sheet(isPresented: $showingNewTarget) {
            AddTargetView(item: item)
        }
        .sheet(isPresented: $showingSettings) {
            AddItemView(editing: item)
        }
        .alert(
            "Delete target?",
            isPresented: Binding(
                get: { targetToDelete != nil },
                set: { if !$0 { targetToDelete = nil } }
            ),
            presenting: targetToDelete
        ) { target in
            Button("Delete", role: .destructive) {
                modelContext.delete(target)
                targetToDelete = nil
            }
            Button("Cancel", role: .cancel) { targetToDelete = nil }
        } message: { target in
            Text("This also deletes its \(target.logs.count) log\(target.logs.count == 1 ? "" : "s"). Archive it instead to keep the history.")
        }
    }
}

/// The item name as the inline navigation title, unless a pager is supplying the title.
private struct ItemPageTitle: ViewModifier {
    let title: String
    let isShown: Bool

    func body(content: Content) -> some View {
        if isShown {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}

private struct TargetCard: View {
    let target: Target
    let color: Color
    let showStatus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(target.cadenceTitle)
                .font(.headline)
            if let summary = target.valueSummary {
                Text(summary)
            }
            Text(target.dateRangeText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if showStatus {
                Text(target.status().title)
                    .font(.caption.bold())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
    }
}

