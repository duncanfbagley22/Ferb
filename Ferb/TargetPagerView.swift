import SwiftUI
import SwiftData

/// Where a target pager opens: the area whose active targets you can swipe between,
/// and the item that was tapped.
struct TargetPagerRoute: Hashable {
    let area: Area
    let startItem: Item
}

/// Swipe between the item pages of one area's active targets, with a status dot per
/// target (like the area pager). Opened by tapping a target card on an area page.
struct TargetPagerView: View {
    @Query(sort: \Target.startDate) private var allTargets: [Target]
    @State private var selection: PersistentIdentifier
    private let area: Area

    init(route: TargetPagerRoute) {
        area = route.area
        _selection = State(initialValue: route.startItem.persistentModelID)
    }

    private struct Page: Identifiable {
        let target: Target
        let item: Item
        var id: PersistentIdentifier { item.persistentModelID }
    }

    /// One page per item with an active target in this area, in the same order as the area page.
    private var pages: [Page] {
        var seen = Set<PersistentIdentifier>()
        return allTargets.active(in: area).compactMap { target in
            guard let item = target.item, seen.insert(item.persistentModelID).inserted else { return nil }
            return Page(target: target, item: item)
        }
    }

    var body: some View {
        let pages = self.pages
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(pages) { page in
                    Capsule()
                        .fill((page.target.status() as TargetStatus?).color)
                        .frame(width: page.id == selection ? 28 : 10, height: 10)
                        .onTapGesture { selection = page.id }
                }
            }
            .padding(.vertical, 12)
            .animation(.easeInOut, value: selection)

            TabView(selection: $selection) {
                ForEach(pages) { page in
                    ItemSummaryView(item: page.item, showsTitle: false)
                        .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle(pages.first { $0.id == selection }?.item.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}
