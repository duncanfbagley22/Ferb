import SwiftUI

/// Settings shared by the Home cards.
enum HomeSettings {
    /// `@AppStorage` key: minutes since midnight after which a cap that is still under its
    /// limit counts as held (dark green) on the last day of its period.
    static let capHeldMinutesKey = "capHeldMinutes"
    static let defaultCapHeldMinutes = 22 * 60   // 10:00 PM
}

/// The color group a target's square falls into on a Home card. The declaration order is the
/// order squares are sorted in (what needs attention first, then settled, then "not needed yet").
enum TileGroup: Int, CaseIterable {
    case red          // a cap that has been broken, or a time target logged outside its window
    case yellow       // needed and not met; partly filled with light green when some is logged
    case lightGreen   // progress on a target that isn't needed yet, or a cap still under its limit
    case darkGreen    // met, or a cap that held
    case gray         // not needed yet (long cadence), or set aside with "Not today"

    var color: Color {
        switch self {
        case .red: .red
        case .yellow: .yellow
        case .lightGreen: Color(red: 0.62, green: 0.86, blue: 0.62)
        case .darkGreen: Color(red: 0.05, green: 0.52, blue: 0.22)
        case .gray: Color.gray.opacity(0.35)
        }
    }

    /// Color for the number inside a merged circle.
    var textColor: Color {
        switch self {
        case .red, .darkGreen: .white
        case .yellow, .lightGreen, .gray: .primary
        }
    }
}

/// One target's state on Home.
struct HomeTile {
    let group: TileGroup
    /// Whether this target should hold its area's tint at yellow. A long-cadence target that
    /// isn't needed yet doesn't, and neither does a cap that is still under its limit.
    let needsAttention: Bool
    /// How far along a partly done target is (0 to 1), drawn as a light green fill inside a
    /// yellow square. Nil for everything else.
    var progress: Double? = nil
}

extension Target {
    /// The square this target gets on a Home card.
    ///
    /// - Binary: yellow until done, then dark green.
    /// - Amount / duration: yellow with nothing logged. Once some is logged it stays yellow while it is
    ///   still needed, filled with light green by how far along it is; dark green when met. If it isn't
    ///   needed yet (long cadence), progress shows as solid light green instead.
    /// - Time targets: yellow until met; red once a log misses the window (nothing more to do), then
    ///   dark green if met. (The latest log counts, so a period longer than a day only turns red on its
    ///   last day.)
    /// - Cap: light green while under the limit, dark green once it's the last day of the period and
    ///   `capHeldMinutes` has passed, red once broken.
    /// - A target with a cadence longer than 2 days is gray until it's needed: planned today, or 2 or
    ///   fewer days left in its period. A target set aside with "Not today" is gray too.
    func homeTile(
        asOf now: Date = .now,
        capHeldMinutes: Int = HomeSettings.defaultCapHeldMinutes,
        calendar: Calendar = .current
    ) -> HomeTile {
        guard let item, let current = recentPeriods(1, asOf: now, calendar: calendar).first(where: \.isCurrent) else {
            return HomeTile(group: .darkGreen, needsAttention: false)
        }
        let today = calendar.startOfDay(for: now)
        let daysLeft = max(1, calendar.dateComponents([.day], from: today, to: current.end).day ?? 1)

        if item.quantityDirection == .cap {
            if current.result == .missed { return HomeTile(group: .red, needsAttention: true) }
            let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            let held = daysLeft == 1 && minutes >= capHeldMinutes
            return HomeTile(group: held ? .darkGreen : .lightGreen, needsAttention: false)
        }

        switch current.result {
        case .done:
            return HomeTile(group: .darkGreen, needsAttention: false)
        case .upcoming, .missed:
            return HomeTile(group: .gray, needsAttention: false)
        case .open:
            break
        }

        // A time target with a log that missed its window has nothing left to do today, so it
        // is red, like a broken cap, rather than yellow.
        if item.quantitySubtype == .timeTarget, current.loggedValue != nil, daysLeft == 1 {
            return HomeTile(group: .red, needsAttention: true)
        }

        let hasProgress = item.trackingType == .quantity
            && item.quantitySubtype != .timeTarget
            && (current.loggedValue ?? 0) > 0
        let weekday = calendar.component(.weekday, from: now)
        let plannedToday = item.planEntries.contains { entry in
            if let date = entry.date { return calendar.isDate(date, inSameDayAs: now) }
            return entry.weekday == weekday
        }
        let needed = intervalDays <= 2 || plannedToday || daysLeft <= 2
        let setAside = (snoozedUntil ?? .distantPast) > now
        let attention = needed && !setAside

        if hasProgress {
            if attention {
                // Still wanted: stays yellow, filled with light green by how far along it is.
                let goal = value ?? 0
                let fraction: Double? = goal > 0 ? min(1, max(0, (current.loggedValue ?? 0) / goal)) : nil
                return HomeTile(group: .yellow, needsAttention: true, progress: fraction)
            }
            return HomeTile(group: .lightGreen, needsAttention: false)
        }
        return HomeTile(group: attention ? .yellow : .gray, needsAttention: attention)
    }
}

extension Collection where Element == Target {
    /// One tile per active target in the area.
    func homeTiles(
        in area: Area,
        asOf now: Date = .now,
        capHeldMinutes: Int = HomeSettings.defaultCapHeldMinutes
    ) -> [HomeTile] {
        active(in: area, asOf: now).map { $0.homeTile(asOf: now, capHeldMinutes: capHeldMinutes) }
    }
}

extension Collection where Element == HomeTile {
    /// The area's tint: nil with no targets, yellow while anything needs attention, otherwise green.
    /// Same never-red rule as `overallStatus`.
    var homeStatus: TargetStatus? {
        guard !isEmpty else { return nil }
        return contains { $0.needsAttention } ? .due : .done
    }
}

// MARK: - Layout

/// A square or circle on a card's mini grid, with its position.
struct PlacedTile: Identifiable {
    let id: Int
    let group: TileGroup
    let count: Int       // targets this shape stands for (1 for a plain square)
    let isMerged: Bool   // a circle with a number in it, instead of a plain square
    let span: Int        // 1 or 2 slots wide and tall
    let col: Int
    let row: Int
    var progress: Double? = nil   // fill level for a partly done square
}

/// Every card has the same 4 x 3 grid of slots, so the four cards are always the same size.
/// With up to 12 targets each gets its own square. With more, whole color groups merge into
/// circles with a count inside, settled ones first (dark green, gray, light green), then yellow,
/// then red. A group of 5 or more becomes a big circle (2 x 2 slots, at most two per card); a
/// smaller group, or any group once both big circles are used, becomes a one-slot circle.
enum HomeTileLayout {
    static let columns = 4
    static let rows = 3
    static let capacity = columns * rows
    static let maxBigCircles = 2

    static func place(_ tiles: [HomeTile]) -> [PlacedTile] {
        var counts: [TileGroup: Int] = [:]
        for tile in tiles { counts[tile.group, default: 0] += 1 }

        // Decide which groups merge. true = big circle, false = one-slot circle, nil = squares.
        var merged: [TileGroup: Bool] = [:]
        var cells = tiles.count
        var bigUsed = 0
        for group in [TileGroup.darkGreen, .gray, .lightGreen, .yellow, .red] {
            guard cells > capacity else { break }
            let n = counts[group, default: 0]
            guard n >= 2 else { continue }
            let big = n >= 5 && bigUsed < maxBigCircles
            cells -= n - (big ? 4 : 1)
            if big { bigUsed += 1 }
            merged[group] = big
        }

        // Big circles take the bottom two 2 x 2 blocks; everything else fills the free
        // slots from the top, sorted by group, so what needs attention sits first.
        var placed: [PlacedTile] = []
        var occupied = Set<Int>()
        var nextID = 0
        var bigIndex = 0
        for group in TileGroup.allCases where merged[group] == true {
            let col = bigIndex * 2
            bigIndex += 1
            for r in 1...2 { for c in col...(col + 1) { occupied.insert(r * columns + c) } }
            placed.append(PlacedTile(id: nextID, group: group, count: counts[group] ?? 0,
                                     isMerged: true, span: 2, col: col, row: 1))
            nextID += 1
        }

        var free = (0..<capacity).filter { !occupied.contains($0) }.makeIterator()
        for group in TileGroup.allCases {
            guard let n = counts[group] else { continue }
            switch merged[group] {
            case true?:
                continue
            case false?:
                guard let cell = free.next() else { continue }
                placed.append(PlacedTile(id: nextID, group: group, count: n, isMerged: true,
                                         span: 1, col: cell % columns, row: cell / columns))
                nextID += 1
            case nil:
                for tile in tiles where tile.group == group {
                    guard let cell = free.next() else { break }
                    placed.append(PlacedTile(id: nextID, group: group, count: 1, isMerged: false,
                                             span: 1, col: cell % columns, row: cell / columns,
                                             progress: tile.progress))
                    nextID += 1
                }
            }
        }
        return placed
    }
}

/// The mini grid inside an area card. Always the same shape, whatever it holds.
struct HomeTileGrid: View {
    let tiles: [HomeTile]
    private let spacing: CGFloat = 6

    var body: some View {
        let placed = HomeTileLayout.place(tiles)
        GeometryReader { geo in
            let columns = CGFloat(HomeTileLayout.columns)
            let cell = (geo.size.width - spacing * (columns - 1)) / columns
            ZStack(alignment: .topLeading) {
                ForEach(placed) { tile in
                    let side = cell * CGFloat(tile.span) + spacing * CGFloat(tile.span - 1)
                    HomeTileShape(tile: tile)
                        .frame(width: side, height: side)
                        .offset(x: CGFloat(tile.col) * (cell + spacing),
                                y: CGFloat(tile.row) * (cell + spacing))
                }
            }
        }
        .aspectRatio(CGFloat(HomeTileLayout.columns) / CGFloat(HomeTileLayout.rows), contentMode: .fit)
    }
}

private struct HomeTileShape: View {
    let tile: PlacedTile

    var body: some View {
        ZStack {
            if tile.isMerged {
                Circle().fill(tile.group.color)
                Text("\(tile.count)")
                    .font(tile.span == 2 ? Font.title2.bold() : Font.caption.bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(tile.group.textColor)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(tile.group.color)
                    .overlay(alignment: .bottom) {
                        if let progress = tile.progress {
                            GeometryReader { geo in
                                TileGroup.lightGreen.color
                                    .frame(height: geo.size.height * progress)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
