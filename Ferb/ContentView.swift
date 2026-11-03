import SwiftUI
import SwiftData
import UIKit

private enum AppTab: Hashable {
    case home, calendar, history, settings
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var targets: [Target]
    @Query private var planEntries: [PlanEntry]
    @State private var selectedTab: AppTab = .home
    @State private var homePath = NavigationPath()
    @State private var showingQuickUpdate = false
    private var router = NotificationRouter.shared

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

    /// Changes when the active targets, the set of targets left to log, or the planned slots
    /// change, which is everything the evening and plan alerts depend on. Logging, undoing,
    /// archiving, adding a target or editing a slot all show up here, so no other screen has to
    /// tell the scheduler anything.
    private var schedulingSignature: String {
        let active = targets.filter { $0.isActive() }.count
        let left = targets.filter { $0.needsQuickLog() }
            .map { String(describing: $0.persistentModelID) }
            .sorted()
            .joined(separator: ",")
        let plan = planEntries.map {
            "\($0.weekday).\($0.startMinutes).\($0.durationMinutes).\($0.date?.timeIntervalSince1970 ?? 0).\($0.item?.name ?? "").\($0.item?.isArchived == true)"
        }
        .sorted()
        .joined(separator: ",")
        return "\(active)|\(left)|\(plan)"
    }

    /// Opens Quick update for a tapped start-of-day / end-of-day alert, but only once the app is
    /// active. The sheet is shown after a short pause so it doesn't collide with the app coming
    /// to the foreground (or finishing launch), which made it flicker or get dropped.
    private func openQuickUpdateIfRequested() {
        guard router.quickUpdateRequested, scenePhase == .active else { return }
        router.quickUpdateRequested = false
        selectedTab = .home
        homePath = NavigationPath()
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            showingQuickUpdate = true
        }
    }

    var body: some View {
        TabView(selection: tabSelection) {
            HomeView(path: $homePath, openFocus: { showingQuickUpdate = true })
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)
            HistoryView()
                .tabItem { Label("History", systemImage: "chart.bar") }
                .tag(AppTab.history)
            SettingsView(resetNavigation: { homePath = NavigationPath() })
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .onAppear {
            // Make sure the built-in subareas exist (adds only the missing ones).
            Subarea.seedDefaults(in: modelContext)
            // Make sure the morning and evening alerts exist.
            Reminder.seedDefaults(in: modelContext)
        }
        .sheet(isPresented: $showingQuickUpdate) {
            QuickInputView()
        }
        .onChange(of: router.quickUpdateRequested, initial: true) { _, _ in
            // A start-of-day or end-of-day alert was tapped: go to Home and open Today's focus.
            openQuickUpdateIfRequested()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Keep the scheduled notifications in step with the saved alerts.
            if phase == .active {
                // A tap that arrived while the app was still coming forward is handled now.
                openQuickUpdateIfRequested()
                Task { await ReminderScheduler.refresh(in: modelContext, requestingPermission: false) }
            }
        }
        .onChange(of: schedulingSignature) {
            Task { await ReminderScheduler.refresh(in: modelContext, requestingPermission: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            // The day rolled over (or the clock/time zone changed) while the app was open.
            Task { await ReminderScheduler.refresh(in: modelContext, requestingPermission: false) }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Item.self, Subarea.self, Target.self, Log.self, Note.self, Reminder.self, CustomUnit.self, PlanEntry.self], inMemory: true)
}
