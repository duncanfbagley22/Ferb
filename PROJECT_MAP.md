# Project Map: FirstApp (iOS Habit Tracker)

_Last updated: 2026-10-04 (aligned to the Figma wireframe: five tabs, item/target screens, Record, Calendar, History placeholder)_

## Overview
- **Project Type**: Native iOS app, SwiftUI + SwiftData (iOS 17+)
- **Purpose**: Personal health/habit tracker organized into four fixed areas (Surface, Structure, Internal, Regulation) and 34 subareas. **Items** are definitions of things that can be measured; **Targets** are what you act on (cadence, start date, window, goal value, tolerance). Logs record completions, with a value for measured items.
- **Tech Stack**: Swift, SwiftUI, SwiftData (local on-device storage, no backend yet)

## Directory Structure
```
FirstApp/                      # Xcode project root
├── FirstApp.xcodeproj/         # Uses synchronized folders: new files in FirstApp/FirstApp are picked up automatically
├── .git/
├── _removed/                   # Files taken out of the build (TargetsView.swift, Cadence.swift) — safe to delete
└── FirstApp/                   # Source folder
    ├── FirstAppApp.swift        # @main entry point, SwiftData container (Item, Target, Log)
    ├── ContentView.swift        # Root TabView: Home / Calendar / Record / History / Settings
    ├── Area.swift                # Area enum (4 fixed areas)
    ├── Subarea.swift              # Subarea enum (34 cases), each maps to one Area
    ├── Item.swift                  # @Model — a definition: name, subarea, how it's measured, priority flag, log method
    ├── Target.swift                 # @Model — what you act on: cadence, window, goal, tolerance + tolerance mode
    ├── Log.swift                     # @Model — a single completion record (optional value), belongs to a Target
    ├── TrackingType.swift             # enums: binary/quantity + subtypes, direction, units, ToleranceMode, TrackingMethod
    ├── TargetStatus.swift              # done/due/overdue (rolling interval) — Target.status()
    ├── TargetPeriods.swift              # derived per-period results with tolerance-aware "done" — Target.periods()
    ├── AreaStatus.swift                  # active-target filter + rollup -> area color/status
    ├── TargetRow.swift                    # shared target row UI + swipe-to-complete + goal summary + number/clock formatters
    ├── ItemRow.swift                       # item row (link to item page + heart toggle) + Item.typeSummary
    ├── AddItemView.swift                    # sheet form to create an Item in a given area (incl. "Log with" method)
    ├── AddTargetView.swift                   # sheet form to create a Target (ends the item's earlier targets)
    ├── HomeView.swift                         # 2x2 area grid, focus banner, profile button, nav destinations
    ├── AreaPagerView.swift                     # horizontal pager between the 4 areas + status dots + add-item +
    ├── AreaDetailView.swift                     # per area: body map above item list, vertical paging snap
    ├── ItemSummaryView.swift                     # item page: current target, previous targets, new target / item settings
    ├── TargetDetailView.swift                     # target page: numbered period rows + stats placeholder
    ├── RecordView.swift                            # Record tab: method hub + per-method logging screens
    ├── CalendarView.swift                           # Calendar tab: month/week views, filters, entries
    ├── HistoryView.swift                             # History tab placeholder: summary cards + badge grid
    ├── QuickInputView.swift                           # end-of-day quick update sheet (from Home focus banner)
    ├── PlaceholderViews.swift                          # SettingsView, PlaceholderSheet (generic stand-in)
    └── Assets.xcassets/                                 # App icon, accent color
```

## Key Files
- **FirstAppApp.swift** — SwiftData `Schema([Item.self, Target.self, Log.self])`, on-disk container
- **TrackingType.swift** — enums describing *what* an item measures, plus `TrackingMethod` (*how* it's logged) and `ToleranceMode`
- **TargetPeriods.swift** — the done/missed logic used by target detail and Calendar
- No README.md in the repo yet.

## Dependencies
None — pure SwiftUI + SwiftData, no SPM packages.

## Design Intent (from the Figma wireframe)
- **Five tabs**: Home, Calendar, Record, History, Settings.
- **Flow**: Home → area pager → body map / item list (vertical snap) → item page (current + previous targets; white button = item settings, black = new target) → target page (numbered periods with done marks, stats block).
- **Record**: one fixed tracking method per item (check, number, timer, NFC). Pick a method, pick an item that uses it, reset or confirm.
- **Colors are placeholders**; green/pink-red only signal status.
- **History** is meant as progress/badges/streaks; **Settings** has no planned contents yet.

## Source Structure

**Data layer**
- `Area` (enum): `.surface` (A), `.structure` (B), `.internals` (C, displays "Internal"), `.regulation` (D). Exposes `letter` and `title`.
- `Subarea` (enum): 34 cases, stable string raw values (don't rename without a migration). Computed `area` and `title`.
- `Item` (`@Model`): `name`, `subarea`, `createdAt`, tracking fields (`trackingType`, `binarySubtype?`, `quantitySubtype?`, `quantityDirection?`, `unit?`), `isPriority` (the heart; sorts the area list), `method: TrackingMethod?`, and `targets` (cascade delete). Computed `area` and `effectiveMethod` (stored method, else derived: binary → check, duration → timer, other quantity → number). New fields all have defaults for lightweight migration.
- `Target` (`@Model`): `item?`, `startDate` (start of day), `durationDays?` (nil = ongoing), `intervalDays` (cadence), `value?` (goal, or minutes since midnight for time targets), `tolerance?`, `toleranceMode` (absolute or percent; percent = % of goal, absolute only for time targets), `reward?` (unused), `logs` (cascade). Computed: `area`, `cadenceTitle`, `lastCompletedAt`, `endDate()`, `isActive(asOf:)`, `dateRangeText`. A new target ends the item's earlier running targets (their `durationDays` is trimmed to stop the day before the new start).
- `Log` (`@Model`): `target?`, `completedAt`, `value: Double?` (minutes for timers, typed number, or minutes since midnight for time targets; nil for plain checks and for logs from swipe/Mark done).
- `TrackingType.swift` enums: `TrackingType` (binary/quantity), `BinarySubtype` (didIt/avoidedIt/stateCheck), `QuantitySubtype` (amount/duration/timeTarget), `QuantityDirection` (cap/target), `ToleranceMode` (absolute/percent), `TrackingMethod` (check/number/timer/nfc; `options(for:quantitySubtype:)` lists valid methods per item type), `QuantityUnit`.
- `TargetStatus` (`TargetStatus.swift`): `.done` / `.due` / `.overdue`, rolling-interval logic from the last log. Value-blind. Drives Home, pager dots, area rows.
- `TargetPeriods.swift`: `Target.periods()` returns one `TargetPeriod` per cadence interval (whole window for finite targets, start through current for ongoing) with a `PeriodResult` (done / missed / open / upcoming). Done rules: binary = any log; amount/duration = logs summed, within tolerance of the goal (at least for `.target`, at most for `.cap`); time target = latest log within ± tolerance minutes; logs with no value count as met (caps are never broken by them). A cap stays open until its period ends.
- `AreaStatus.swift`: `active(in:)`, `overallStatus`, and `Optional<TargetStatus>.color`.

**UI layer**
- `ContentView` — TabView: Home, Calendar, Record, History, Settings.
- `HomeView` — 2x2 `AreaCard` grid with progress rings; "Today's focus" banner opens `QuickInputView`; profile button opens a placeholder sheet. Owns navigation destinations for `Area`, `Item`, `Target`.
- `AreaPagerView` — horizontal `TabView(.page)` across the 4 areas, status dots, nav-bar `+` opens `AddItemView` for the selected area.
- `AreaDetailView` — per area, a vertical `ScrollView` with `.scrollTargetBehavior(.paging)`: body map placeholder first (arrow button jumps down), then the list (arrow button jumps up). The list is a `LazyVStack` (not a `List`), so swipe actions don't work: long-press menus provide "Mark done" and "Delete target" on target rows and "Delete" (with confirmation) on item rows.
- `ItemRow` — tappable text opens the item page; separate heart button toggles `isPriority`.
- `ItemSummaryView` — current target card, horizontal strip of ended targets (cards open `TargetDetailView`), "Item settings" (name, priority) and "New target" (opens `AddTargetView(item:)`).
- `TargetDetailView` — header with goal/date range/"N of M periods done", numbered period rows (status color, value, mark), scrolls to the current period, stats placeholder block.
- `RecordView` — hub of four methods → `RecordMethodView`: picks among active targets whose item uses that method; check (tap circle), number (arrows + typed value, step scaled to goal; time wheel for time targets), timer (tap ring, saves minutes), NFC (placeholder that fakes a scan; real CoreNFC needs a physical iPhone). Reset clears; Confirm saves a `Log` (saving immediately) and returns to the hub.
- `CalendarView` — Month/Week toggle, month grid or W1–W5 rows, filter pills (area, status — placeholders), entries for the selected day/week built from `periods()`; entries open the item page. Ongoing targets aren't projected into the future.
- `HistoryView` — static summary cards and a locked badge grid (placeholder).
- `QuickInputView` — lists active targets; check items can be marked done right there, others point to Record.
- `AddItemView(area:)` — name, fixed area, subarea, Binary/Quantity with subtype/direction/unit, and a "Log with" picker when more than one method fits.
- `AddTargetView(item:)` — item picker (preselectable), schedule, goal, tolerance with absolute/percent picker (time targets absolute only).
- `TargetRow` — target row with swipe-to-complete (only works inside a `List`; currently unused for logging since the area list is no longer a `List`), plus `Target.valueSummary`, `formatted`, `clock`.
- `PlaceholderViews.swift` — `SettingsView` (text stub) and `PlaceholderSheet`.

## Entry Points
- App launch → `FirstAppApp` → `ContentView` (TabView) → Home first.

## Configuration & Environment
- No `.env` or secrets — local SwiftData storage, `isStoredInMemoryOnly: false`. No CloudKit yet.
- Schema changes with defaults migrate automatically; anything else may require deleting the app to reset the store.
- Logs are saved explicitly (`modelContext.save()`) right after insertion so status updates immediately.

## Notable Patterns / Conventions
- **Items are definitions, targets are actions**: cadence, logs and status live on `Target`.
- **Two "done" systems exist side by side**: `Target.status()` (rolling due/overdue, value-blind) powers Home, pager dots and rows; `Target.periods()` (window-based, tolerance-aware) powers target detail and Calendar. Unifying them is a likely future step.
- **Status is computed, never stored**, as are periods and area.
- **Filtering happens in Swift, not SwiftData predicates** (`@Query` fetches all; small data).
- **Time targets** store minutes since midnight; near-midnight tolerance would need wraparound-aware math.
- **UI is intentionally placeholder-grade** (SF Symbols, default colors).

## Open Questions / Gaps
- Pending renames: binary subtypes to success/avoidance, quantity direction to maximum/minimum (`.target` collides conceptually with the Target model).
- Swipe-to-log is gone from the area list; logging there is long-press "Mark done" (no value). A visible per-row check button could replace it.
- Targets with a future start date aren't visible or deletable anywhere (area list shows active, item page shows current and ended). An "Upcoming" section on the item page would fix it.
- Items can be deleted only from the area list long-press menu (deleting from the item page risks a crash on the open page); no way to undo or delete a `Log`; no target editing.
- NFC is a placeholder (planned: real CoreNFC or Shortcuts automation → App Intent).
- Status and period states don't refresh at midnight while the app stays open.
- Nothing rolls a target over when its window ends.
- Calendar filter pills, History cards/badges, Settings contents, Profile, and body-map tappable regions are all undecided.
- No per-area item limit enforced (mentioned in the original sketch).
- Reward is an unused placeholder String on `Target`.
