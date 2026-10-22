import SwiftUI
import SwiftData

private enum CalendarMode: String, CaseIterable, Identifiable {
    case month = "Month"
    case week = "Week"

    var id: String { rawValue }
}

/// Targets that pass the calendar filters, each with its periods worked out.
private typealias FilteredTargets = [(target: Target, periods: [TargetPeriod])]

/// One target's showing in the selected day or week.
private struct CalendarEntry: Identifiable {
    let item: Item
    let target: Target
    let periods: [TargetPeriod]

    var id: PersistentIdentifier { target.persistentModelID }

    var doneCount: Int { periods.filter { $0.result == .done }.count }

    /// Worst result wins: any miss shows as missed, all done shows as done.
    var result: PeriodResult { combinedResult(of: periods) }
}

/// Worst result wins: any miss shows as missed, all done shows as done.
private func combinedResult(of periods: [TargetPeriod]) -> PeriodResult {
    if periods.contains(where: { $0.result == .missed }) { return .missed }
    if periods.allSatisfy({ $0.result == .done }) { return .done }
    return periods.allSatisfy({ $0.result == .upcoming }) ? .upcoming : .open
}

/// How a day (or week) is colored in the calendar.
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
        case .future: Color.secondary.opacity(0.12)
        case .open: Color.secondary.opacity(0.3)
        case .done: Color.green.opacity(0.35)
        case .missed: Color.red.opacity(0.35)
        case .mixed: Color.orange.opacity(0.35)
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

/// Month and week views of what's tracked when. Pick a day (or a week) to see its items;
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

    private let calendar = Calendar.current

    var body: some View {
        // Worked out once per update and shared by the grid, the week rows and the list.
        let all = filteredPeriods
        return NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    filterPills

                    Picker("View", selection: $mode) {
                        ForEach(CalendarMode.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    monthHeader

                    if mode == .month {
                        monthGrid(all)
                    } else {
                        weekRows(all)
                    }

                    Divider()

                    entryList(all)
                }
                .padding()
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

    // MARK: - Month and week pickers

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
                .foregroundStyle(Color.primary)
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

    /// The displayed month split into weeks, with the first and last clipped to the month.
    private var weeks: [Range<Date>] {
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: displayedMonth) else { return [] }
        var result: [Range<Date>] = []
        var cursor = displayedMonth
        while cursor < monthEnd {
            let weekEnd = min(calendar.dateInterval(of: .weekOfYear, for: cursor)?.end ?? monthEnd, monthEnd)
            result.append(cursor..<weekEnd)
            cursor = weekEnd
        }
        return result
    }

    private func weekRows(_ all: FilteredTargets) -> some View {
        let states = weekStates(all)
        return VStack(spacing: 8) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                let isSelected = week.contains(selectedDay)
                let tint = states[index].tint ?? Color.secondary.opacity(0.05)
                Button { selectedDay = week.lowerBound } label: {
                    HStack {
                        Text("W\(index + 1)")
                            .bold()
                        Spacer()
                        Text(rangeLabel(week))
                            .font(.subheadline)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color.primary)
                    .background(tint, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12).stroke(Color.primary, lineWidth: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rangeLabel(_ range: Range<Date>) -> String {
        let last = calendar.date(byAdding: .day, value: -1, to: range.upperBound) ?? range.upperBound
        let start = range.lowerBound.formatted(.dateTime.month(.abbreviated).day())
        let end = last.formatted(.dateTime.month(.abbreviated).day())
        return start == end ? start : "\(start) – \(end)"
    }

    // MARK: - Entries

    private var selectedRange: Range<Date> {
        switch mode {
        case .month:
            let end = calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
            return selectedDay..<end
        case .week:
            return weeks.first { $0.contains(selectedDay) } ?? (selectedDay..<selectedDay)
        }
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
            let entry = CalendarEntry(item: item, target: element.target, periods: overlapping)
            if let statusFilter, entry.result != statusFilter { return nil }
            return entry
        }
    }

    /// The color state for a day or week, following the area, subarea and status filters.
    private func state(
        for range: Range<Date>,
        in all: [(target: Target, periods: [TargetPeriod])]
    ) -> DayState {
        let today = calendar.startOfDay(for: .now)
        if range.lowerBound > today { return .future }

        var done = 0, missed = 0, open = 0
        for element in all {
            let overlapping = element.periods.filter {
                $0.start < range.upperBound && $0.end > range.lowerBound
            }
            guard !overlapping.isEmpty else { continue }
            let result = combinedResult(of: overlapping)
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

    /// State for each week row, in the same order as `weeks`.
    private func weekStates(_ all: FilteredTargets) -> [DayState] {
        weeks.map { state(for: $0, in: all) }
    }

    private var selectionTitle: String {
        switch mode {
        case .month: selectedDay.formatted(date: .complete, time: .omitted)
        case .week: "Week of \(rangeLabel(selectedRange))"
        }
    }

    private func entryList(_ all: FilteredTargets) -> some View {
        let shown = entries(all)
        return VStack(alignment: .leading, spacing: 0) {
            Text(selectionTitle)
                .font(.headline)
                .padding(.bottom, 8)
            if shown.isEmpty {
                Text("Nothing here")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(shown) { entry in
                    NavigationLink(value: entry.item) {
                        entryRow(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        switch mode {
        case .month: entry.target.cadenceTitle
        case .week: "\(entry.doneCount) of \(entry.periods.count) periods done"
        }
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
        case .done: .green
        case .missed: .red
        case .open, .upcoming: .gray
        }
    }
}
