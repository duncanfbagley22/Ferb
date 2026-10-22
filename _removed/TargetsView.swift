import SwiftUI
import SwiftData

struct TargetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Target.startDate) private var targets: [Target]
    @State private var showingAdd = false

    private var today: Date { Calendar.current.startOfDay(for: .now) }

    private var active: [Target] {
        targets.filter { $0.isActive() }
    }

    private var upcoming: [Target] {
        targets.filter { Calendar.current.startOfDay(for: $0.startDate) > today }
    }

    private var ended: [Target] {
        targets.filter {
            !$0.isActive() && Calendar.current.startOfDay(for: $0.startDate) <= today
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if targets.isEmpty {
                    ContentUnavailableView(
                        "No targets yet",
                        systemImage: "scope",
                        description: Text("Targets are what you act on. Tap + to set one for an item.")
                    )
                } else {
                    List {
                        Section("Active") {
                            if active.isEmpty {
                                Text("No active targets")
                                    .foregroundStyle(.secondary)
                            } else {
                                rows(active, canLog: true)
                            }
                        }
                        if !upcoming.isEmpty {
                            Section("Upcoming") { rows(upcoming, canLog: false) }
                        }
                        if !ended.isEmpty {
                            Section("Ended") { rows(ended, canLog: false) }
                        }
                    }
                }
            }
            .navigationTitle("Targets")
            .toolbar {
                Button("Add", systemImage: "plus") { showingAdd = true }
            }
            .sheet(isPresented: $showingAdd) {
                AddTargetView()
            }
        }
    }

    private func rows(_ list: [Target], canLog: Bool) -> some View {
        ForEach(list) { target in
            TargetRow(target: target, canLog: canLog)
                .contextMenu {
                    Button(role: .destructive) {
                        modelContext.delete(target)
                    } label: {
                        Label("Delete target", systemImage: "trash")
                    }
                }
        }
    }
}

#Preview {
    TargetsView()
        .modelContainer(for: [Item.self, Target.self, Log.self], inMemory: true)
}
