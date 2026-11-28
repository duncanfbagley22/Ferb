import SwiftUI
import SwiftData

private enum CalendarMode: String, CaseIterable, Identifiable {
    case month = "Month"
    case plan = "Plan"

    var id: String { rawValue }
}

/// Targets that pass the calendar filters, each with its periods worked out.
private typealias FilteredTargets = [(target: Target, periods: [TargetPeriod])]

/// One target's showing in the selected day.
private struct CalendarEntry: Identifiable {
    let item: Item
    let target: Target
    let periods: [TargetPeriod]
    /// Count each day once: the selected day has a log, so it reads as done whatever its period says.
    var loggedOnDay: Bool = false

    var id: PersistentIdentifier { target.persistentModelID }

    /// Worst result wins: any miss shows as missed, all done shows as done.
    var result: PeriodResult { loggedOnDay ? .done : combinedResult(of: periods) }
}

/// Worst result wins: any miss shows as missed, all done shows as done.
private func combinedResult(of periods: [TargetPeriod]) -> PeriodResult {
    combinedResult(ofResults: periods.map(\.result))
}

/// Same rule over plain results (used for an area group's header).
private func combinedResult(ofResults results: [PeriodResult]) -> PeriodResult {
    if results.contains(.missed) { return .missed }
    if results.allSatisfy({ $0 == .done }) { return .done }
    return results.allSatisfy({ $0 == .upcoming }) ? .upcoming : .open
}

/// One area's entries for the selected day. `area` is nil for items whose subarea has no area.
private struct AreaEntryGroup: Identifiable {
    let area: Area?
    let entries: [CalendarEntry]

    var id: String { area?.title ?? "Other" }
    var title: String { area?.title ?? "Other" }
    var result: PeriodResult { combinedResult(ofResults: entries.map(\.result)) }
}

/// How a day is colored in the calendar.
private enum DayState {
    case none      // nothing tracked
    case future    // hasn't happened yet
    case open      // today or earlier, nothing resolved yet
    case done      // everything tracked was done
    case missed    // everything tracked was missed
    case mixed     // some done, some missed or still open

    var tint: Color? {
        switch self {
        case .none: nil
        case .future: Color.gray.opacity(0.35)
        case .open, .mixed: Color.yellow
        case .done: Color.goalMet
        case .missed: Color.goalMissed
        }
    }

    /// Day-number color that stays readable on the tint.
    var textColor: Color {
        switch self {
        case .done, .missed: .white
        case .open, .mixed: .black
        case .none, .future: .primary
        }
    }
}

private extension PeriodResult {
    var title: String {
        switch self {
        case .done: "Done"
        case .missed: "Missed"
        case .open: "Open"
        case .upcoming: "Upcoming"
        }
    }
}

/// Month view of what's tracked when (plus the Plan tab). Pick a day to see its items;
/// tap an item to open it. Ongoing targets aren't projected into the future.
struct CalendarView: View {
    @Query(sort: \Target.startDate) private var targets: [Target]
    @Query(sort: \Subarea.sortOrder) private var subareas: [Subarea]

    @State private var mode: CalendarMode = .month
    @State private var displayedMonth: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start
        ?? Calendar.current.startOfDay(for: .now)
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var areaFilter: Area?
    @State private var subareaFilter: Subarea?
    @State private var statusFilter: PeriodResult?
    /// Area groups open in the day list (all start collapsed; kept when you change day).
    @State private var expandedAreas: Set<Area?> = []

    private let calendar = Calendar.current

    var body: some View {
        // Worked out once per update and shared by the grid and the list.
        let all = mode == .plan ? [] : filteredPeriods
        return NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    ForEach(CalendarMode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

                if mode == .plan {
                    PlanView()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            filterPills

                            monthHeader

                            monthGrid(all)

                            Divider()

                            entryList(all)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Calendar")
            .onChange(of: areaFilter) {
                // The subarea filter only exists under an area: clear it when the area is
                // cleared or changed to a different one.
                if areaFilter == nil || subareaFilter?.area != areaFilter {
                    subareaFilter = nil
                }
            }
            .navigationDestination(for: Item.self) { item in
                ItemSummaryView(item: item)
            }
            .navigationDestination(for: Target.self) { target in
                TargetDetailView(target: target)
            }
        }
    }

    // MARK: - Filters

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Menu {
                    Picker("Area", selection: $areaFilter) {
                        Text("All areas").tag(Area?.none)
                        ForEach(Area.allCases) { area in
                            Text(area.title).tag(Area?.some(area))
                        }
                    }
                } label: {
                    pill(areaFilter?.title ?? "All areas")
                }

                if let areaFilter {
                    Menu {
                        Picker("Subarea", selection: $subareaFilter) {
                            Text("All subareas").tag(Subarea?.none)
                            ForEach(subareas.filter { $0.area == areaFilter }) { subarea in
                                Text(subarea.title).tag(Subarea?.some(subarea))
                            }
                        }
                    } label: {
                        pill(subareaFilter?.title ?? "All subareas")
                    }
                }

                Menu {
                    Picker("Status", selection: $statusFilter) {
                        Text("Any status").tag(PeriodResult?.none)
                        ForEach([PeriodResult.done, .missed, .open], id: \.self) { result in
                            Text(result.title).tag(PeriodResult?.some(result))
                        }
                    }
                } label: {
                    pill(statusFilter?.title ?? "Any status")
                }
            }
        }
    }

    private func pill(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.15), in: Capsule())
    }

    // MARK: - Month picker

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button { shiftMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
        }
    }

    private func shiftMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = next
        if !calendar.isDate(selectedDay, equalTo: next, toGranularity: .month) {
            selectedDay = next
        }
    }

    private func monthGrid(_ all: FilteredTargets) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let states = dayStates(all)
        return VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day, state: states[day] ?? .none)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date, state: DayState) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        return Button { selectedDay = day } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.subheadline.weight(isSelected ? .bold : .regular))
                .foregroundStyle(state.textColor)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(state.tint ?? Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8).stroke(Color.primary, lineWidth: 2)
                    } else if isToday {
                        RoundedRectangle(cornerRadius: 8).stroke(Color.secondary, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// The month's days, padded with blanks so the first lands on the right weekday.
    private var gridDays: [Date?] {
        guard let days = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: displayedMonth)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        for day in days {
            result.append(calendar.date(byAdding: .day, value: day - 1, to: displayedMonth))
        }
        return result
    }

    // MARK: - Entries

    private var selectedRange: Range<Date> {
        let end = calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
        return selectedDay..<end
    }

    /// Whether a target that counts each day once has a log inside the range (a day).
    private func hasLog(_ target: Target, in range: Range<Date>) -> Bool {
        target.oncePerDay == true
            && target.logs.contains { $0.completedAt >= range.lowerBound && $0.completedAt < range.upperBound }
    }

    /// Targets that pass the area and subarea filters, with their periods worked out once.
    private var filteredPeriods: FilteredTargets {
        targets.compactMap { target in
            guard !target.isHidden, let item = target.item,
                  areaFilter == nil || item.area == areaFilter,
                  subareaFilter == nil || item.subarea == subareaFilter else { return nil }
            return (target: target, periods: target.periods())
        }
    }

    private func entries(_ all: FilteredTargets) -> [CalendarEntry] {
        let range = selectedRange
        return all.compactMap { element in
            guard let item = element.target.item else { return nil }
            let overlapping = element.periods.filter {
                $0.start < range.upperBound && $0.end > range.lowerBound
            }
            guard !overlapping.isEmpty else { return nil }
            let entry = CalendarEntry(
                item: item,
                target: element.target,
                periods: overlapping,
                loggedOnDay: hasLog(element.target, in: range)
            )
            if let statusFilter, entry.result != statusFilter { return nil }
            return entry
        }
    }

    /// What one target contributes to a single day. A one-day period counts on its day. A longer
    /// period counts only on the day it was settled (goal reached, cap broken, or deadline
    /// missed), plus its last day while still open, so a weekly target isn't "due" all week.
    private func dayResult(on day: Date, periods: [TargetPeriod], today: Date) -> PeriodResult? {
        guard let period = periods.first(where: { $0.start <= day && day < $0.end }) else { return nil }
        let length = calendar.dateComponents([.day], from: period.start, to: period.end).day ?? 1
        if length <= 1 { return period.result == .upcoming ? nil : period.result }
        if period.settledOn == day { return period.result }
        let lastDay = calendar.date(byAdding: .day, value: -1, to: period.end) ?? day
        if period.result == .open && day == lastDay && day <= today { return .open }
        return nil
    }

    /// The color state for a day, following the area, subarea and status filters.
    private func state(
        for range: Range<Date>,
        in all: [(target: Target, periods: [TargetPeriod])]
    ) -> DayState {
        let today = calendar.startOfDay(for: .now)
        if range.lowerBound > today { return .future }

        var done = 0, missed = 0, open = 0
        for element in all {
            // Count each day once: a day with a log is done, whatever its period says.
            let result: PeriodResult
            if hasLog(element.target, in: range) {
                result = .done
            } else if let found = dayResult(on: range.lowerBound, periods: element.periods, today: today) {
                result = found
            } else {
                continue
            }
            if let statusFilter, result != statusFilter { continue }
            switch result {
            case .done: done += 1
            case .missed: missed += 1
            case .open: open += 1
            case .upcoming: break
            }
        }

        if done == 0 && missed == 0 && open == 0 { return .none }
        if missed == 0 && open == 0 { return .done }
        if done == 0 && open == 0 { return .missed }
        if done == 0 && missed == 0 { return .open }
        return .mixed
    }

    /// State for each day of the displayed month, keyed by the day's start.
    private func dayStates(_ all: FilteredTargets) -> [Date: DayState] {
        var result: [Date: DayState] = [:]
        for case let day? in gridDays {
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            result[day] = state(for: day..<end, in: all)
        }
        return result
    }

    private var selectionTitle: String {
        selectedDay.formatted(date: .complete, time: .omitted)
    }

    private func entryList(_ all: FilteredTargets) -> some View {
        let groups = areaGroups(entries(all))
        return VStack(alignment: .leading, spacing: 0) {
            Text(selectionTitle)
                .font(.headline)
                .padding(.bottom, 8)
            if groups.isEmpty {
                Text("Nothing here")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groups) { group in
                    let isExpanded = expandedAreas.contains(group.area)
                    groupHeader(group, isExpanded: isExpanded)
                    if isExpanded {
                        ForEach(group.entries) { entry in
                            NavigationLink(value: entry.item) {
                                entryRow(entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The day's entries grouped by area in the usual area order, with an "Other" group last.
    private func areaGroups(_ shown: [CalendarEntry]) -> [AreaEntryGroup] {
        var groups: [AreaEntryGroup] = []
        for area in Area.allCases {
            let matching = shown.filter { $0.item.area == area }
            if !matching.isEmpty { groups.append(AreaEntryGroup(area: area, entries: matching)) }
        }
        let other = shown.filter { $0.item.area == nil }
        if !other.isEmpty { groups.append(AreaEntryGroup(area: nil, entries: other)) }
        return groups
    }

    /// Tap to open or close the group. The icon is the group's worst result.
    private func groupHeader(_ group: AreaEntryGroup, isExpanded: Bool) -> some View {
        let result = group.result
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded {
                    expandedAreas.remove(group.area)
                } else {
                    expandedAreas.insert(group.area)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: result))
                    .font(.title3)
                    .foregroundStyle(color(for: result))
                Text(group.title)
                    .font(.headline)
                Text("\(group.entries.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    private func entryRow(_ entry: CalendarEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: entry.result))
                .font(.title3)
                .foregroundStyle(color(for: entry.result))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.item.name)
                Text(subtitle(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(color(for: entry.result).opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 8)
    }

    private func subtitle(for entry: CalendarEntry) -> String {
        entry.target.cadenceTitle
    }

    private func icon(for result: PeriodResult) -> String {
        switch result {
        case .done: "checkmark.circle.fill"
        case .missed: "xmark.circle.fill"
        case .open: "circle"
        case .upcoming: "circle.dashed"
        }
    }

    private func color(for result: PeriodResult) -> Color {
        switch result {
        case .done: Color.goalMet
        case .missed: Color.goalMissed
        case .open: .yellow
        case .upcoming: .gray
        }
    }
}
