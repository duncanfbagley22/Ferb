import SwiftUI
import SwiftData

private struct PlacedEntry: Identifiable {
    let entry: PlanEntry
    let column: Int
    let columns: Int

    var id: PersistentIdentifier { entry.persistentModelID }
}

/// The plan: pick a day and see its slots on a day timeline. Add a slot with +, tap one to
/// edit it, long-press to delete it. Slots overlapping in time sit side by side. With calendar
/// access allowed, the day's calendar events show as soft bands behind the slots (arrows step
/// one day at a time), so you can plan around them.
struct PlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \PlanEntry.startMinutes) private var allEntries: [PlanEntry]

    private let calendarStore = CalendarEventsStore.shared
    private var capacity = AlertCapacity.shared

    /// The day being shown (start of day).
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var showingAdd = false
    @State private var editing: PlanEntry?

    private let hourHeight: CGFloat = 100
    private let labelWidth: CGFloat = 52

    /// The slots on the date being shown: weekly ones for this weekday, plus one-offs set for
    /// exactly this date. Slots whose item is archived are left out.
    private var entries: [PlanEntry] {
        let calendar = Calendar.current
        let day = planDate
        return allEntries.filter { entry in
            guard entry.item != nil, entry.item?.isArchived != true else { return false }
            if let date = entry.date { return calendar.isDate(date, inSameDayAs: day) }
            return entry.weekday == weekday
        }
    }

    /// The shown day's weekday number (1 = Sunday).
    private var weekday: Int {
        Calendar.current.component(.weekday, from: selectedDate)
    }

    /// The seven days of the week containing the shown day, from the user's first weekday.
    private var weekDates: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var dayName: String {
        Calendar.current.weekdaySymbols[weekday - 1]
    }

    /// The hour the timeline scrolls to: 5 AM, or an hour before the day's first slot if earlier.
    private var startHour: Int {
        let earliest = entries.map(\.startMinutes).min() ?? 5 * 60
        return max(0, min(5, earliest / 60 - 1))
    }

    /// The date being shown.
    private var planDate: Date { selectedDate }

    private var dateLabel: String {
        planDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var calendarEvents: [DayEvent] {
        _ = calendarStore.revision  // re-read when the Calendar app's data changes
        return calendarStore.events(on: planDate)
    }

    var body: some View {
        let events = calendarEvents
        return VStack(spacing: 0) {
            weekdayStrip
            calendarBar(events)

            let clashCount = entries.filter { overlapsEvent($0, in: events) }.count
            if clashCount > 0 {
                Text("\(clashCount) slot\(clashCount == 1 ? "" : "s") overlap\(clashCount == 1 ? "s" : "") a calendar event on \(dateLabel).")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }
            if capacity.droppedPlan > 0 {
                let count = capacity.droppedPlan
                Text("\(count) plan alert\(count == 1 ? " isn't" : "s aren't") scheduled: over iOS's notification limit. See Settings → Alerts.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            if entries.isEmpty {
                Text("Nothing planned for \(dayName). Tap + to add a slot.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    timeline(events)
                        .padding(.vertical, 8)
                }
                .onAppear { proxy.scrollTo(startHour, anchor: .top) }
                .onChange(of: selectedDate) {
                    proxy.scrollTo(startHour, anchor: .top)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if calendarStore.isAuthorized {
                    Menu {
                        calendarMenu
                    } label: {
                        Label("Calendars", systemImage: "calendar")
                    }
                }
                Button("Add slot", systemImage: "plus") { showingAdd = true }
            }
        }
        .sheet(isPresented: $showingAdd) {
            PlanEntryEditor(editing: nil, weekday: weekday, date: planDate, onSavedOneOff: jump(to:))
        }
        .sheet(item: $editing) { entry in
            PlanEntryEditor(editing: entry, weekday: entry.weekday, date: planDate, onSavedOneOff: jump(to:))
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from iOS Settings: pick up a changed calendar permission.
            if phase == .active { calendarStore.refreshStatus() }
        }
    }

    /// After saving a one-off slot, show the day it's on.
    private func jump(to date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
    }

    private func shiftDay(by days: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
    }

    // MARK: - Week strip

    /// The week containing the shown day, with real dates. Tap a day to show it.
    private var weekdayStrip: some View {
        let calendar = Calendar.current
        return HStack(spacing: 6) {
            ForEach(weekDates, id: \.self) { date in
                let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                let isToday = calendar.isDateInToday(date)
                Button { selectedDate = date } label: {
                    VStack(spacing: 2) {
                        Text(calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1])
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(calendar.component(.day, from: date))")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(isSelected ? Color.accentColor : Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Calendar bar

    /// Under the weekday strip: a button to allow calendar access, a note if it's off, or (once
    /// allowed) the date being shown with day arrows and all-day events.
    @ViewBuilder
    private func calendarBar(_ events: [DayEvent]) -> some View {
        dateBar

        if calendarStore.isAuthorized {
            let allDay = events.filter(\.isAllDay)
            if !allDay.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(allDay) { event in
                            Text(event.title)
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(event.color.opacity(0.25), in: Capsule())
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)
            }
        } else if calendarStore.canAsk {
            Button {
                Task { await calendarStore.requestAccess() }
            } label: {
                Label("Show calendar events", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .padding(.bottom, 8)
        } else {
            HStack {
                Text("Calendar access is off.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Settings") {
                    if let url = ReminderScheduler.settingsURL { openURL(url) }
                }
                .font(.subheadline)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    /// The date being shown with day arrows (and a Today button once you've moved off today).
    /// The calendar picker lives in the toolbar beside +.
    private var dateBar: some View {
        HStack(spacing: 8) {
            Button { shiftDay(by: -1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Previous day")
            Text(dateLabel)
                .font(.subheadline.weight(.medium))
            Button { shiftDay(by: 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Next day")
            Spacer()
            if !Calendar.current.isDateInToday(selectedDate) {
                Button("Today") { selectedDate = Calendar.current.startOfDay(for: .now) }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var calendarMenu: some View {
        ForEach(calendarStore.groups) { group in
            Section(group.title) {
                ForEach(group.calendars) { calendar in
                    Toggle(
                        calendar.title,
                        isOn: Binding(
                            get: { !calendarStore.isHidden(calendar.id) },
                            set: { calendarStore.setHidden(calendar.id, hidden: !$0) }
                        )
                    )
                }
            }
        }
    }

    // MARK: - Timeline

    private func timeline(_ events: [DayEvent]) -> some View {
        let placed = layout(entries)
        let timed = events.filter { !$0.isAllDay }
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    HStack(alignment: .top, spacing: 8) {
                        Text(hourLabel(hour))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: labelWidth - 8, alignment: .trailing)
                            .offset(y: -7)
                        VStack(spacing: 0) {
                            Divider()
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: hourHeight)
                    .id(hour)
                }
            }

            GeometryReader { geo in
                let width = geo.size.width - labelWidth

                // Calendar events sit behind your slots.
                ForEach(timed) { event in
                    eventBand(event)
                        .frame(width: width - 3, height: bandHeight(event), alignment: .topLeading)
                        .offset(x: labelWidth, y: CGFloat(event.startMinutes) / 60 * hourHeight)
                        .allowsHitTesting(false)
                }

                ForEach(placed) { item in
                    block(for: item.entry, clashes: overlapsEvent(item.entry, in: timed))
                        .frame(
                            width: width / CGFloat(item.columns) - 3,
                            height: blockHeight(item.entry),
                            alignment: .topLeading
                        )
                        .offset(
                            x: labelWidth + width / CGFloat(item.columns) * CGFloat(item.column),
                            y: CGFloat(item.entry.startMinutes) / 60 * hourHeight
                        )
                }
            }
        }
        .frame(height: hourHeight * 24)
        .padding(.horizontal)
    }

    private func eventBand(_ event: DayEvent) -> some View {
        Text(event.title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(event.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
    }

    private func bandHeight(_ event: DayEvent) -> CGFloat {
        max(20, CGFloat(event.endMinutes - event.startMinutes) / 60 * hourHeight)
    }

    /// Whether a slot overlaps a timed calendar event on the date being shown.
    private func overlapsEvent(_ entry: PlanEntry, in events: [DayEvent]) -> Bool {
        events.contains {
            !$0.isAllDay && $0.startMinutes < entry.endMinutes && $0.endMinutes > entry.startMinutes
        }
    }

    private func block(for entry: PlanEntry, clashes: Bool) -> some View {
        Button { editing = entry } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.item?.name ?? "Item")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if blockHeight(entry) >= 44 {
                    Text("\(Target.clock(minutes: entry.startMinutes)) – \(Target.clock(minutes: entry.endMinutes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.accentColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                if clashes {
                    RoundedRectangle(cornerRadius: 6).stroke(Color.orange, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) {
                modelContext.delete(entry)
                try? modelContext.save()
            }
        }
    }

    private func blockHeight(_ entry: PlanEntry) -> CGFloat {
        max(24, CGFloat(entry.endMinutes - entry.startMinutes) / 60 * hourHeight)
    }

    private func hourLabel(_ hour: Int) -> String {
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve) \(hour < 12 ? "AM" : "PM")"
    }

    /// Gives each slot a column so overlapping ones sit side by side instead of on top of
    /// each other. Slots that don't overlap anything use the full width.
    private func layout(_ entries: [PlanEntry]) -> [PlacedEntry] {
        var result: [PlacedEntry] = []
        var cluster: [(entry: PlanEntry, column: Int)] = []
        var columnEnds: [Int] = []
        var clusterEnd = 0

        for entry in entries.sorted(by: { $0.startMinutes < $1.startMinutes }) {
            if !cluster.isEmpty && entry.startMinutes >= clusterEnd {
                let count = columnEnds.count
                result += cluster.map { PlacedEntry(entry: $0.entry, column: $0.column, columns: count) }
                cluster = []
                columnEnds = []
            }
            let end = entry.endMinutes
            if let column = columnEnds.firstIndex(where: { $0 <= entry.startMinutes }) {
                columnEnds[column] = end
                cluster.append((entry, column))
            } else {
                columnEnds.append(end)
                cluster.append((entry, columnEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, end)
        }
        let count = max(columnEnds.count, 1)
        result += cluster.map { PlacedEntry(entry: $0.entry, column: $0.column, columns: count) }
        return result
    }
}

// MARK: - Add / edit a slot

/// Adds a slot (to one or more weekdays at once) or edits one. When adding, the length starts
/// at the item's duration goal if it has one.
struct PlanEntryEditor: View {
    let editing: PlanEntry?
    /// Called after saving a one-off slot, so the plan can show the day it landed on.
    let onSavedOneOff: (Date) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Item> { $0.isArchived == false }, sort: \Item.name) private var items: [Item]
    @Query private var allEntries: [PlanEntry]

    @State private var item: Item?
    @State private var start: Date
    @State private var duration: Int
    @State private var days: Set<Int>
    @State private var durationTouched = false
    /// false = a one-off slot on `oneOffDate`; true = repeats weekly on `days`.
    @State private var repeats: Bool
    @State private var oneOffDate: Date

    init(
        editing: PlanEntry?,
        weekday: Int,
        date: Date = .now,
        onSavedOneOff: @escaping (Date) -> Void = { _ in }
    ) {
        self.editing = editing
        self.onSavedOneOff = onSavedOneOff
        if let editing {
            _item = State(initialValue: editing.item)
            _start = State(initialValue: Self.date(minutes: editing.startMinutes))
            _duration = State(initialValue: editing.durationMinutes)
            _days = State(initialValue: [editing.weekday])
            _repeats = State(initialValue: editing.date == nil)
            _oneOffDate = State(initialValue: editing.date ?? date)
        } else {
            _item = State(initialValue: nil)
            _start = State(initialValue: Self.date(minutes: 7 * 60))
            _duration = State(initialValue: 15)
            _days = State(initialValue: [weekday])
            // New slots default to just the day being shown; switch to "Every week" to repeat.
            _repeats = State(initialValue: false)
            _oneOffDate = State(initialValue: date)
        }
    }

    private static func date(minutes: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: (minutes / 60) % 24, minute: minutes % 60)) ?? .now
    }

    private static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private var lengthText: String {
        let hours = duration / 60, minutes = duration % 60
        if hours == 0 { return "\(minutes) min" }
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }

    /// The selected days on which this weekly slot would overlap another weekly slot.
    private var overlappingDays: [Int] {
        guard item != nil else { return [] }
        let startMinutes = Self.minutes(from: start)
        let endMinutes = min(startMinutes + duration, 24 * 60)
        return days.sorted().filter { day in
            allEntries.contains { other in
                other !== editing && other.date == nil && other.weekday == day
                    && other.item?.isArchived != true
                    && other.startMinutes < endMinutes && other.endMinutes > startMinutes
            }
        }
    }

    /// Whether this one-off slot would overlap another slot that falls on the same date
    /// (a one-off for that date, or a weekly slot for that weekday).
    private var overlapsOnDate: Bool {
        guard item != nil else { return false }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: oneOffDate)
        let startMinutes = Self.minutes(from: start)
        let endMinutes = min(startMinutes + duration, 24 * 60)
        return allEntries.contains { other in
            guard other !== editing, other.item?.isArchived != true else { return false }
            let sameDay = other.date.map { calendar.isDate($0, inSameDayAs: oneOffDate) }
                ?? (other.weekday == weekday)
            return sameDay && other.startMinutes < endMinutes && other.endMinutes > startMinutes
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Item", selection: $item) {
                        Text("Select…").tag(nil as Item?)
                        ForEach(Area.allCases) { area in
                            let areaItems = items.filter { $0.area == area }
                            if !areaItems.isEmpty {
                                Section(area.title) {
                                    ForEach(areaItems) { option in
                                        Text(option.name).tag(Optional(option))
                                    }
                                }
                            }
                        }
                    }
                    .pickerStyle(.navigationLink)

                    DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)

                    Stepper(
                        "Length: \(lengthText)",
                        value: Binding(
                            get: { duration },
                            set: { duration = $0; durationTouched = true }
                        ),
                        in: 5...480,
                        step: 5
                    )
                }

                Section {
                    Picker("Schedule", selection: $repeats) {
                        Text("Just this day").tag(false)
                        Text("Every week").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if repeats {
                        HStack(spacing: 6) {
                            ForEach(orderedWeekdays, id: \.self) { day in
                                dayButton(day)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        DatePicker(
                            "Date",
                            selection: $oneOffDate,
                            in: min(Calendar.current.startOfDay(for: .now), oneOffDate)...,
                            displayedComponents: .date
                        )
                    }
                } header: {
                    Text(repeats ? (editing == nil ? "Repeat on" : "Day") : "When")
                } footer: {
                    if repeats, !overlappingDays.isEmpty {
                        let names = overlappingDays.map { Calendar.current.shortWeekdaySymbols[$0 - 1] }
                        Text("Overlaps another slot on \(names.joined(separator: ", ")). It will sit beside it.")
                    } else if !repeats, overlapsOnDate {
                        Text("Overlaps another slot that day. It will sit beside it.")
                    }
                }

                if let editing {
                    Section {
                        Button("Delete slot", systemImage: "trash", role: .destructive) {
                            modelContext.delete(editing)
                            try? modelContext.save()
                            dismiss()
                        }
                    }
                }
            }
            .onChange(of: item) {
                // A new slot starts at the item's duration goal until you change the length.
                if editing == nil, !durationTouched, let item {
                    duration = item.defaultPlanMinutes
                }
            }
            .navigationTitle(editing == nil ? "New slot" : "Edit slot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(item == nil || days.isEmpty)
                }
            }
        }
    }

    private func dayButton(_ day: Int) -> some View {
        let isOn = days.contains(day)
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

    /// Adding can pick several days; editing moves the one slot to a single day.
    private func toggle(_ day: Int) {
        if editing != nil {
            days = [day]
        } else if days.contains(day) {
            if days.count > 1 { days.remove(day) }
        } else {
            days.insert(day)
        }
    }

    private func save() {
        guard let item else { return }
        let startMinutes = Self.minutes(from: start)
        // A slot can't run past midnight.
        let length = min(duration, 24 * 60 - startMinutes)

        let calendar = Calendar.current
        let oneOff = calendar.startOfDay(for: oneOffDate)
        let oneOffWeekday = calendar.component(.weekday, from: oneOff)

        if let editing {
            editing.item = item
            editing.startMinutes = startMinutes
            editing.durationMinutes = length
            if repeats {
                editing.date = nil
                if let day = days.first { editing.weekday = day }
            } else {
                editing.date = oneOff
                editing.weekday = oneOffWeekday
            }
        } else if repeats {
            for day in days {
                modelContext.insert(PlanEntry(
                    item: item,
                    weekday: day,
                    startMinutes: startMinutes,
                    durationMinutes: length
                ))
            }
        } else {
            modelContext.insert(PlanEntry(
                item: item,
                weekday: oneOffWeekday,
                startMinutes: startMinutes,
                durationMinutes: length,
                date: oneOff
            ))
        }
        try? modelContext.save()
        dismiss()
        if !repeats { onSavedOneOff(oneOff) }
    }
}
