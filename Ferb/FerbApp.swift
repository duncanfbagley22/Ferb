import SwiftUI
import SwiftData
import UserNotifications

/// The in-app light/dark override. "System" follows the phone's setting.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Nil means "don't override".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@main
struct FerbApp: App {
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    var sharedModelContainer: ModelContainer = {
        // If you add a model here, also add it to deleteAllData() in SettingsView (PlaceholderViews.swift),
        // or "Delete all data" will leave that model's rows behind.
        let schema = Schema([Item.self, Subarea.self, Target.self, Log.self, Note.self, Reminder.self, CustomUnit.self, PlanEntry.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // Register early so a tap that launches the app is delivered too.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}
