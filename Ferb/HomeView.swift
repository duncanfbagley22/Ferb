import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var path: NavigationPath
    /// Opens Today's focus (Quick update). The sheet itself lives in `ContentView`.
    var openFocus: () -> Void
    @Query(sort: \Target.startDate) private var targets: [Target]
    @AppStorage(HomeSettings.capHeldMinutesKey) private var capHeldMinutes = HomeSettings.defaultCapHeldMinutes
    @State private var showingProfile = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    // Re-evaluated every minute so the cap threshold and midnight are picked up
                    // while Home stays open.
                    TimelineView(.everyMinute) { context in
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(Area.allCases) { area in
                                NavigationLink(value: area) {
                                    AreaCard(
                                        area: area,
                                        tiles: targets.homeTiles(
                                            in: area,
                                            asOf: context.date,
                                            capHeldMinutes: capHeldMinutes
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button { openFocus() } label: {
                        FocusBanner()
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Profile", systemImage: "person.crop.circle") { showingProfile = true }
                }
            }
            .sheet(isPresented: $showingProfile) {
                PlaceholderSheet(title: "Profile", message: "Profile will go here.")
            }
            .navigationDestination(for: Area.self) { area in
                AreaPagerView(start: area)
            }
            .navigationDestination(for: Item.self) { item in
                ItemSummaryView(item: item)
            }
            .navigationDestination(for: TargetPagerRoute.self) { route in
                TargetPagerView(route: route)
            }
            .navigationDestination(for: Target.self) { target in
                TargetDetailView(target: target)
            }
        }
    }
}

private struct FocusBanner: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's focus")
                    .font(.headline)
                Text("Tap to log today's progress")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// An area card: the area name over a fixed 4 x 3 grid with one square per active target
/// (see `HomeTiles.swift`). The tint is the area's overall status.
private struct AreaCard: View {
    let area: Area
    let tiles: [HomeTile]

    private var color: Color { tiles.homeStatus.color }

    var body: some View {
        VStack(spacing: 10) {
            Text(area.title)
                .font(.headline)
            HomeTileGrid(tiles: tiles)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(area.title), \(tiles.filter(\.needsAttention).count) of \(tiles.count) targets need attention")
    }
}

#Preview {
    HomeView(path: .constant(NavigationPath()), openFocus: {})
        .modelContainer(for: [Item.self, Subarea.self, Target.self, Log.self, Note.self], inMemory: true)
}
