import SwiftUI
import SwiftData

struct AreaPagerView: View {
    @Query(sort: \Target.startDate) private var allTargets: [Target]
    @Query(sort: \Item.name) private var allItems: [Item]
    @State private var selection: Area
    @State private var showingAddItem = false
    @State private var showingAddTarget = false
    /// The item just created, held until the add-item sheet closes so we can suggest a target.
    @State private var pendingItem: Item?
    @State private var showingTargetPrompt = false
    @State private var targetItem: Item?

    init(start: Area) {
        _selection = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(Area.allCases) { area in
                    Capsule()
                        .fill(targets(in: area).overallStatus.color)
                        .frame(width: area == selection ? 28 : 10, height: 10)
                        .onTapGesture { selection = area }
                }
            }
            .padding(.vertical, 12)
            .animation(.easeInOut, value: selection)

            TabView(selection: $selection) {
                ForEach(Area.allCases) { area in
                    AreaDetailView(area: area)
                        .tag(area)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle(selection.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New item", systemImage: "square.and.pencil") { showingAddItem = true }
                    Button("New target", systemImage: "scope") { showingAddTarget = true }
                        .disabled(!allItems.contains { $0.area == selection && !$0.isArchived })
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel("Add")
                }
            }
        }
        .sheet(isPresented: $showingAddItem, onDismiss: {
            if pendingItem != nil { showingTargetPrompt = true }
        }) {
            AddItemView(area: selection) { item in
                pendingItem = item
            }
        }
        .alert("Set a target?", isPresented: $showingTargetPrompt, presenting: pendingItem) { item in
            Button("Create target") {
                targetItem = item
                pendingItem = nil
            }
            Button("Not now", role: .cancel) {
                pendingItem = nil
            }
        } message: { item in
            Text("\(item.name) won't be tracked until it has a target. You can also add one later from the item's page.")
        }
        .sheet(item: $targetItem) { item in
            AddTargetView(item: item)
        }
        .sheet(isPresented: $showingAddTarget) {
            AddTargetView(limitToArea: selection)
        }
    }

    private func targets(in area: Area) -> [Target] {
        allTargets.active(in: area)
    }
}
