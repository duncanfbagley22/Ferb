import SwiftUI
import SwiftData
import UserNotifications

/// Settings → Alerts. The morning and evening alerts, plus any custom reminders.
struct AlertsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reminder.createdAt) private var reminders: [Reminder]
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    /// The Plan alerts switch. Off until turned on; the scheduler reads the same setting.
    @AppStorage(ReminderScheduler.planAlertsKey) private var planAlertsEnabled = false
    private var capacity = AlertCapacity.shared

    /// Whether iOS currently lets the app send notifications.
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    /// The reminder whose edit screen is open (an existing one, or a newly added one).
    @State private var editing: Reminder?

    private var builtIns: [Reminder] {
        [ReminderKind.morning, .evening].compactMap { kind in
            reminders.first { $0.kind == kind }
        }
    }

    private var customReminders: [Reminder] {
        reminders.filter { $0.kind == .custom }
    }

    /// Changes whenever any alert's settings change, so the notifications get rebuilt.
    private var signature: [String] {
        reminders.map {
            "\($0.kind.rawValue)|\($0.label)|\($0.hour):\($0.minute)|\($0.weekdays.sorted())|\($0.isEnabled)"
        } + ["plan|\(planAlertsEnabled)"]
    }

    /// Says so before plan alerts start going missing, and again once they have. Nil when
    /// there's nothing to report.
    private var capacityWarning: (title: String, detail: String, isProblem: Bool)? {
        let budget = ReminderScheduler.pendingBudget
        if capacity.droppedPlan > 0 {
            let count = capacity.droppedPlan
            return (
                "\(count) plan alert\(count == 1 ? "" : "s") not scheduled",
                "iOS lets an app keep 64 notifications waiting, and Ferb stays under \(budget). The latest plan alerts are left out and come back as earlier ones go off, each time you open the app. To fit them now, remove plan slots or turn off other alerts.",
                true
            )
        }
        if capacity.failed > 0 {
            let count = capacity.failed
            return (
                "iOS refused \(count) alert\(count == 1 ? "" : "s")",
                "They weren't scheduled. Reopening the app tries again; if it keeps happening, check notification settings.",
                true
            )
        }
        if capacity.scheduled > ReminderScheduler.systemLimit {
            return (
                "Too many alerts",
                "Start of day, end of day and custom alerts alone are over iOS's limit of 64, so some won't go off. Remove some custom alerts or days.",
                true
            )
        }
        if planAlertsEnabled, capacity.isNearLimit {
            return (
                "Close to the limit",
                "\(capacity.scheduled) of \(budget) notifications are in use. Adding more plan slots or alerts may leave some out.",
                false
            )
        }
        return nil
    }

    var body: some View {
        List {
            if authStatus == .denied {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notifications are turned off for this app, so alerts can't go off.")
                        Button("Open iOS Settings") {
                            if let url = ReminderScheduler.settingsURL { openURL(url) }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section {
                ForEach(builtIns) { reminder in
                    row(for: reminder)
                }
            } footer: {
                Text("Start of day is a nudge to open Today's focus. End of day only goes off if something is still untracked.")
            }

            Section {
                Toggle("Plan alerts", isOn: $planAlertsEnabled)
                if let warning = capacityWarning {
                    VStack(alignment: .leading, spacing: 6) {
                        Label {
                            Text(warning.title)
                        } icon: {
                            Image(systemName: warning.isProblem ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                .foregroundStyle(warning.isProblem ? Color.orange : Color.yellow)
                        }
                        Text(warning.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Goes off when a planned slot starts (Calendar → Plan), only if that item still needs logging. Scheduled a few days ahead, so open the app now and then.")
            }

            Section("Custom") {
                ForEach(customReminders) { reminder in
                    row(for: reminder)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                modelContext.delete(reminder)
                                try? modelContext.save()
                            }
                        }
                }
                Button {
                    addReminder()
                } label: {
                    Label("Add reminder", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editing) { reminder in
            ReminderEditView(reminder: reminder)
        }
        .task(id: signature) {
            authStatus = await ReminderScheduler.refresh(in: modelContext, requestingPermission: true)
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from iOS Settings: pick up a changed permission.
            if phase == .active {
                Task { authStatus = await ReminderScheduler.currentStatus() }
            }
        }
    }

    private func row(for reminder: Reminder) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.displayTitle)
                Text(reminder.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { editing = reminder }

            Toggle("On", isOn: Binding(
                get: { reminder.isEnabled },
                set: { reminder.isEnabled = $0 }
            ))
            .labelsHidden()
        }
    }

    private func addReminder() {
        let reminder = Reminder(kind: .custom, hour: 12, isEnabled: true)
        modelContext.insert(reminder)
        try? modelContext.save()
        editing = reminder
    }
}

/// Edit one alert: its label (custom only), on/off, time, and which days it repeats.
struct ReminderEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var reminder: Reminder

    /// Changes whenever this alert's settings change.
    private var signature: String {
        "\(reminder.label)|\(reminder.hour):\(reminder.minute)|\(reminder.weekdays.sorted())|\(reminder.isEnabled)"
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { reminder.timeOfDay },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminder.hour = parts.hour ?? reminder.hour
                reminder.minute = parts.minute ?? reminder.minute
            }
        )
    }

    /// Weekday numbers starting from the user's first day of the week.
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        Form {
            if reminder.kind == .custom {
                Section("Label") {
                    TextField("Reminder", text: $reminder.label)
                }
            }

            Section {
                Toggle("On", isOn: $reminder.isEnabled)
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
            }

            Section("Repeat") {
                HStack(spacing: 6) {
                    ForEach(orderedWeekdays, id: \.self) { day in
                        dayButton(day)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(reminder.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: signature) {
            // Wait briefly so typing a label or spinning the time picker rebuilds once, not per tick.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await ReminderScheduler.refresh(in: modelContext, requestingPermission: true)
        }
        .onDisappear {
            // Catch a change made just before leaving the screen.
            Task { await ReminderScheduler.refresh(in: modelContext, requestingPermission: true) }
        }
    }

    private func dayButton(_ day: Int) -> some View {
        let isOn = reminder.weekdays.contains(day)
        return Button {
            toggle(day)
        } label: {
            Text(Calendar.current.shortWeekdaySymbols[day - 1])
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isOn ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.borderless)
    }

    /// Flips a day on or off. The last remaining day can't be turned off, so an
    /// enabled alert always has somewhere to go off (turn the alert off instead).
    private func toggle(_ day: Int) {
        if reminder.weekdays.contains(day) {
            guard reminder.weekdays.count > 1 else { return }
            reminder.weekdays.removeAll { $0 == day }
        } else {
            reminder.weekdays.append(day)
        }
    }
}
