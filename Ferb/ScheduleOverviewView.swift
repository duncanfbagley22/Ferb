import SwiftUI
import SwiftData

/// The whole plan at a glance, opened from the Plan toolbar: each weekday's slots with the day's
/// planned time, the one-off slots still to come, and the active targets that have no slot.
/// Only slots whose item has an active target count (the same rule the day timeline uses).
struct ScheduleOverviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PlanEntry.startMinutes) private var allEntries: [PlanEntry]
    @Query private var allTargets: [Target]

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: .now) }

    /// Weekly slots whose item has a target active today.
    private var weeklyEntries: [PlanEntry] {
        allEntries.filter { $0.date == nil && $0.isShown(on: today) }
    }

    /// One-off slots from today on whose item has a target active on that date.
    private var upcomingOneOffs: [PlanEntry] {
        allEntries
            .filter { entry in
                guard let date = entry.date, date >= today else { return false }
                return entry.isShown(on: date)
            }
            .sorted {
                ($0.date ?? .distantFuture, $0.startMinutes) < ($1.date ?? .distantFuture, $1.startMinutes)
            }
    }

    /// Weekday numbers (1 = Sunday) starting from the user's first weekday.
    private var weekdayOrder: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private var weeklyMinutes: Int {
        weeklyEntries.reduce(0) { $0 + $1.durationMinutes }
    }

    /// Items with an active target that appear in no weekly or upcoming one-off slot.
    private var unscheduledItems: [Item] {
        let planned = Set((weeklyEntries + upcomingOneOffs).compactMap { $0.item?.persistentModelID })
        var seen = Set<PersistentIdentifier>()
        return allTargets
            .filter { $0.isActive(asOf: today, calendar: calendar) }
            .compactMap(\.item)
            .filter { item in
                !planned.contains(item.persistentModelID) && seen.insert(item.persistentModelID).inserted
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Weekly slots", value: "\(weeklyEntries.count)")
                    LabeledContent("Planned per week", value: durationText(weeklyMinutes))
                } footer: {
                    Text("Only slots whose item has an active target are counted.")
                }

                ForEach(weekdayOrder, id: \.self) { day in
                    let slots = weeklyEntries.filter { $0.weekday == day }
                    Section {
                        if slots.isEmpty {
                            Text("Nothing planned")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(slots) { entry in
                                slotRow(entry)
                            }
                        }
                    } header: {
                        HStack {
                            Text(calendar.weekdaySymbols[day - 1])
                            Spacer()
                            if !slots.isEmpty {
                                let minutes = slots.reduce(0) { $0 + $1.durationMinutes }
                                Text("\(slots.count) slot\(slots.count == 1 ? "" : "s") · \(durationText(minutes))")
                            }
                        }
                    }
                }

                if !upcomingOneOffs.isEmpty {
                    Section("One-off slots coming up") {
                        ForEach(upcomingOneOffs) { entry in
                            slotRow(entry, dateLabel: entry.date)
                        }
                    }
                }

                if !unscheduledItems.isEmpty {
                    Section {
                        ForEach(unscheduledItems) { item in
                            Text(item.name)
                        }
                    } header: {
                        Text("Active targets with no slot")
                    } footer: {
                        Text("Not every target needs a slot.")
                    }
                }
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func slotRow(_ entry: PlanEntry, dateLabel: Date? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.item?.name ?? "")
                let times = "\(timeText(entry.startMinutes)) – \(timeText(entry.endMinutes))"
                if let dateLabel {
                    Text("\(dateLabel.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(times)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(times)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(durationText(entry.durationMinutes))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func timeText(_ minutes: Int) -> String {
        let date = calendar.date(bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func durationText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
