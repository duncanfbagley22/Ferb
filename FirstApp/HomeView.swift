import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var path: NavigationPath
    @Query(sort: \Target.startDate) private var targets: [Target]
    @State private var showingQuickInput = false
    @State private var showingProfile = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Area.allCases) { area in
                            NavigationLink(value: area) {
                                AreaCard(area: area, targets: targets.active(in: area))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button { showingQuickInput = true } label: {
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
            .sheet(isPresented: $showingQuickInput) {
                QuickInputView()
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

private struct AreaCard: View {
    let area: Area
    let targets: [Target]

    private var color: Color { targets.overallStatus.color }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(area.letter) · \(area.title)")
                .font(.headline)
            Text("\(targets.count)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(targets.count == 1 ? "active target" : "active targets")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal)
        .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    HomeView(path: .constant(NavigationPath()))
        .modelContainer(for: [Item.self, Subarea.self, Target.self, Log.self], inMemory: true)
}
