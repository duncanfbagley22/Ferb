import SwiftUI
import SwiftData

private enum AppTab: Hashable {
    case home, calendar, record, history, settings
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: AppTab = .home
    @State private var homePath = NavigationPath()

    /// Wraps the selection so we can notice a tap on the tab that is already selected.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab, newValue == .home {
                    // Re-tapping Home pops back to its root.
                    homePath = NavigationPath()
                }
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            HomeView(path: $homePath)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)
            RecordView()
                .tabItem { Label("Record", systemImage: "record.circle") }
                .tag(AppTab.record)
            HistoryView()
                .tabItem { Label("History", systemImage: "chart.bar") }
                .tag(AppTab.history)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .onAppear {
            // Make sure the built-in subareas exist (adds only the missing ones).
            Subarea.seedDefaults(in: modelContext)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Item.self, Subarea.self, Target.self, Log.self], inMemory: true)
}
