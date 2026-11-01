# Project Map: Ferb (iOS Habit Tracker)

_Last updated: 2026-11-01. Reflects archiving, item/target editing, the swipe Quick update, log editing, Settings (Appearance, Alerts, Notes, Subareas, Units, Archived, Delete all data), the status/calendar rework (only the current period counts), notifications, Log now (the Record tab was removed), custom units, time-target direction, the Weekly Plan (weekly and one-off slots, read-only calendar events), the timer Live Activity (widget extension), and the rename from FirstApp to Ferb._

## Overview
- **Project Type**: Native iOS app, SwiftUI + SwiftData (iOS 17+)
- **Purpose**: Personal health/habit tracker organized into four fixed areas (Surface, Structure, Internal, Regulation) and 34 built-in subareas (more can be added). **Items** are definitions of things that can be measured; **Targets** are what you act on (cadence, start date, window, goal value, tolerance). **Logs** record completions, with a value for measured items.
- **Tech Stack**: Swift, SwiftUI, SwiftData (local on-device storage, no backend, no sync, no export yet), UserNotifications (local alerts only), EventKit (read-only calendar events), ActivityKit + WidgetKit (timer Live Activity)

## Directory Structure
```
Ferb/                          # Xcode project root
├── Ferb.xcodeproj/             # Uses synchronized folders: new/renamed files in Ferb/Ferb are picked up automatically
├── .git/
├── PROJECT_MAP.md
├── FerbTimerWidget/            # Widget Extension target (synchronized folder): the timer Live Activity
│   ├── FerbTimerWidgetBundle.swift       # @main widget bundle (the Live Activity only)
│   ├── FerbTimerWidgetLiveActivity.swift # FerbTimerAttributes + lock screen / Dynamic Island layout
│   └── Info.plist, Assets.xcassets
├── _removed/                   # Old code outside the build (TargetsView.swift, Cadence.swift, RecordView.swift, FerbTimerWidget.swift = the unused sample widget): safe to delete
└── Ferb/                       # Source folder
    ├── FerbApp.swift            # @main, SwiftData container, AppAppearance (light/dark override), registers the notification tap handler
    ├── ContentView.swift        # Root TabView (Home / Calendar / History / Settings), owns the Quick update sheet, seeds subareas + alerts, keeps notifications in step
    ├── Area.swift                # Area enum (4 fixed areas)
    ├── Subarea.swift              # @Model Subarea + the 34 built-in defaults and seedDefaults
    ├── Item.swift                  # @Model: name, subarea, how it's measured, priority, archived flag, log method
    ├── Target.swift                 # @Model: cadence, window, goal, tolerance, archived flag, saved timer state
    ├── Log.swift                     # @Model: one completion (optional value) + Target.record / Target.remove helpers
    ├── Note.swift                     # @Model: free-form notes (Settings -> Notes)
    ├── Reminder.swift                  # @Model: an alert's settings (kind, label, time, weekdays, on/off) + seedDefaults
    ├── CustomUnit.swift                   # @Model: a unit you added (pushups, glasses); items use one via Item.customUnit
    ├── PlanEntry.swift                    # @Model: a Weekly Plan slot (item, weekday, start, length); optional date = one-off
    ├── TrackingType.swift             # enums: binary/quantity + subtypes, direction, units, ToleranceMode, TimeDirection, TrackingMethod
    ├── TargetStatus.swift              # done/due/overdue, derived from periods
    ├── TargetPeriods.swift              # derived per-period results: periods(), recentPeriods(), settledOn, time-goal rules
    ├── TargetQuickLog.swift              # Target.needsQuickLog(): the one "still needs logging" rule (Quick update + evening alert)
    ├── TargetLogInput.swift               # shared logging inputs: LogInputKind, LogDraft, TargetLogInputs view, timer helpers on Target (also drive the Live Activity)
    ├── TimerActivityAttributes.swift      # the app's copy of FerbTimerAttributes: must match the widget's copy exactly
    ├── TimerActivity.swift                 # starts / pauses / ends the timer's Live Activity (one banner at a time)
    ├── AreaStatus.swift                    # active-target filter + rollup -> area color/status
    ├── TargetRow.swift                      # TargetGridCard (area grid card) + Target.valueSummary / formatted / clock helpers
    ├── ItemRow.swift                         # item row (link to item page + priority star) + Item.typeSummary
    ├── AddItemView.swift                      # create OR edit an item (init(area:) / init(editing:))
    ├── AddTargetView.swift                     # create OR edit a target (init(item:limitToArea:basedOn:) / init(editing:))
    ├── HomeView.swift                           # 2x2 area cards (active-target count + status tint), focus banner, nav destinations
    ├── AreaPagerView.swift                       # horizontal pager between areas + status dots + "+" menu (New item / New target)
    ├── AreaDetailView.swift                       # per area: 3-across target cards, then items without a target
    ├── ItemSummaryView.swift                       # item page: current, upcoming and previous targets, Edit item, New target
    ├── TargetDetailView.swift                       # target page: scrolling period rows, pinned stats block, Log + Edit buttons, log editor sheets
    ├── LogNowView.swift                              # "Log now" sheet: log any single target (caps, already-met, NFC) with the shared inputs
    ├── QuickInputView.swift                           # swipe-through card stack (from the Home focus banner or a tapped alert)
    ├── CalendarView.swift                              # month/week views with progress tints, area/subarea/status filters
    ├── PlanView.swift                      # Weekly Plan: weekday strip, day timeline, slot editor (PlanEntryEditor), calendar bands + clash warning
    ├── CalendarEventsStore.swift            # read-only EventKit wrapper: a day's events, hidden-calendar list
    ├── HistoryView.swift                                # History tab placeholder: summary cards + badge grid
    ├── AlertsView.swift                                  # Settings -> Alerts list + ReminderEditView (time, days, on/off, custom label)
    ├── ReminderScheduler.swift                            # turns Reminders into scheduled local notifications; permission handling
    ├── NotificationRouter.swift                            # notification-center delegate: a tapped morning/evening alert opens Quick update
    ├── NotesView.swift                                      # Settings -> Notes list + editor
    ├── PlaceholderViews.swift                                # SettingsView (incl. Delete all data), SubareasView, ArchivedView, PlaceholderSheet
    ├── UnitsView.swift                       # Settings -> Units: rename custom units, delete ones no item uses
    └── Assets.xcassets/                                       # App icon, accent color
```

## Key Files
- **FerbApp.swift**: `Schema([Item, Subarea, Target, Log, Note, Reminder, CustomUnit, PlanEntry])` (a comment there says: a new model must also be added to `deleteAllData()` in `SettingsView`), on-disk container, the light/dark override stored with `@AppStorage("appearance")`, and in `init()` it sets `NotificationRouter.shared` as the notification delegate (early, so a tap that launches the app is delivered).
- **TargetPeriods.swift**: the single source of truth for done/missed. Status, card dots, Quick update and the Calendar all read from it.
- **TargetQuickLog.swift**: `needsQuickLog()` is the single definition of "this target still needs logging today" (active, current period not met, not a cap, not NFC). Quick update and the evening alert both use it so they never disagree.
- **TargetLogInput.swift**: shared by Quick update and Log now. `Target.logInputKind` (check / amount / duration / durationTimer / time), `LogDraft` (typed number and time, plus `resolve(target)` giving the value to log or a warning), `TargetLogInputs` (the input view, with ± arrows on number fields stepping 1/10/100 by goal size), and timer helpers on `Target` (`timerSeconds`, `toggleTimer`, `clearTimer`), plus `loggedSoFarText`. `toggleTimer` and `clearTimer` also start / pause / end the Live Activity (via `TimerActivity`), so every logging path stays in step without extra calls.
- **Log.swift**: log creation and deletion should always go through `target.record(...)` / `target.remove(...)`.
- No README.md in the repo yet.

## Dependencies
None: pure SwiftUI + SwiftData + UserNotifications + EventKit + ActivityKit/WidgetKit (system frameworks), no SPM packages.

## Data Layer
- `Area` (enum): `.surface` (A), `.structure` (B), `.internals` (C, displays "Internal"), `.regulation` (D). Exposes `letter` and `title`.
- `Subarea` (`@Model`): `key` (stable id; built-ins use the old enum names like "hair", custom ones a UUID), `title`, `area`, `isBuiltIn`, `sortOrder`, `items`. 34 built-ins are seeded by `Subarea.seedDefaults` (adds only missing ones) when `ContentView` appears. Custom ones can be added from the item form and renamed/deleted in Settings → Subareas (deletion only if no item uses it; built-ins can't be deleted).
- `Item` (`@Model`): `name`, `subarea?`, `createdAt`, tracking fields (`trackingType`, `binarySubtype?`, `quantitySubtype?`, `quantityDirection?`, `unit?`), `isPriority`, `isArchived`, `method: TrackingMethod?`, `customUnit?` (a user-added unit, used instead of `unit`, never both), `targets` (cascade), `planEntries` (cascade). Computed: `area` (optional, from the subarea), `unitName` (the unit text every screen shows next to numbers), `effectiveMethod` (stored method, else binary -> check, duration -> timer, other quantity -> number). Today the method only matters for the timer card and for NFC items being left out of Quick update (they're logged manually through Log now until real NFC exists).
- `Target` (`@Model`): `item?`, `startDate`, `durationDays?` (nil = ongoing), `intervalDays`, `value?` (goal, or minutes since midnight for time targets), `tolerance?`, `toleranceMode`, `timeDirectionStored?` (with a computed `timeDirection` that defaults to `.either`; stored as optional so old rows with no value don't crash), `reward?` (unused), `isArchived`, `timerStartedAt?` / `timerAccumulated` (saved timer; survives leaving the screen or closing the app), `logs` (cascade). Computed: `area`, `cadenceTitle`, `lastCompletedAt`, `endDate()`, `isHidden` (archived, or its item is), `isActive(asOf:)` (false when hidden), `dateRangeText`. Creating a new target trims the item's earlier running targets to end the day before.
- `Log` (`@Model`): `target?`, `completedAt`, `value: Double?`. `Target.record(value:at:in:)` creates, attaches to `target.logs` immediately, and saves (so colors update at once); `Target.remove(_:in:)` is the inverse.
- `Note` (`@Model`): `body`, `createdAt`, `updatedAt`; first line is the title.
- `CustomUnit` (`@Model`): `name`, `createdAt`, `items` (nullify). Added from the item form ("New unit…"); renamed or deleted in Settings → Units (deletion blocked while any item, archived ones included, uses it). A name matching a built-in or existing unit selects that one instead of duplicating.
- `PlanEntry` (`@Model`): `weekday` (1 = Sunday), `startMinutes`, `durationMinutes`, `item?` (cascade from `Item.planEntries`), `createdAt`, `date?`. No `date` = weekly slot repeating on that weekday; with a `date` (start of day) = one-off slot shown only that day (`weekday` is then that date's weekday). `endMinutes` is capped at midnight. `Item.defaultPlanMinutes` suggests a length from the item's duration goal.
- `Reminder` (`@Model`): `kind` (`ReminderKind`: morning / evening / custom), `label` (custom only), `hour`, `minute`, `weekdays` (Calendar numbers, 1 = Sunday), `isEnabled`, `createdAt`. `Reminder.seedDefaults` adds the morning (8:00 AM) and evening (8:00 PM) alerts, both off, if missing. Computed: `displayTitle`, `summary`, `daysText`.
- `TrackingType.swift`: `TrackingType` (binary/quantity), `BinarySubtype` (didIt/avoidedIt/stateCheck), `QuantitySubtype` (amount/duration/timeTarget), `QuantityDirection` (cap/target), `ToleranceMode` (absolute/percent), `TrackingMethod` (check/number/timer/nfc; `options(for:quantitySubtype:)`; its `systemImage` is now unused), `QuantityUnit`, `TimeDirection` (either / noLaterThan / noEarlierThan: for time targets, whether early, late or either side counts as on time).

## Status and Period Logic
- `Target.periods()` returns one `TargetPeriod` per cadence interval (whole window if finite, start through current if ongoing) with `result` (done / missed / open / upcoming), `loggedValue` and `settledOn`. Built in a single pass over logs sorted by counting date.
- `Target.recentPeriods(n)` builds only the last n started periods; use it where only the latest few matter (status, card dots, Quick update).
- Done rules: binary = any log; amount/duration = logs summed within tolerance (at least the goal for `.target`, at most for `.cap`); time target = latest log within ± tolerance minutes using the short way around the clock. Logs with no value count as met (a cap is never broken by them). A cap stays open until its period ends.
- **Evening time goals** (goal at or after noon, like a bedtime): a log with a clock time before noon counts toward the previous day's period (`countingDate(of:)`); `isEveningTimeGoal`.
- `settledOn`: the day the period's outcome was fixed: goal first met, cap first broken, or the last day if missed / a cap held. Nil while open.
- `Target.status()` (done / due / overdue) reads only the current period (`recentPeriods(1)`): done if it's met, upcoming, or a cap that hasn't been broken; due if it's open (non-cap); overdue only when a cap has already been broken this period. A missed earlier period never changes the color; it only shows in the history dots. It drives Home tints, pager dots, area grid card tints and the item page.
- `AreaStatus.swift`: `active(in:)`, `overallStatus` (green when every target is done, yellow when any is still open; never red, since a broken cap is a today-only fact), `Optional<TargetStatus>.color`.

## Alerts (Notifications)
- **Settings → Alerts** (`AlertsView`): the two built-ins (Start of day, End of day) and any number of custom reminders. Each has an on/off toggle; tapping opens `ReminderEditView` (time, days of the week, label for custom). The last remaining day can't be turned off. New custom reminders start on.
- **Scheduling** (`ReminderScheduler.refresh`): clears every pending request it made (ids start with `reminder.`) and rebuilds from the saved reminders.
  - Morning and custom: one repeating weekly request per enabled weekday. Morning text: "Today's focus" / "Open the app to see what's on today." (generic on purpose, so it's never stale). Custom: the label as the title.
  - Evening: a rolling window of one-off requests for the next 14 days ("End of day" / "Anything left to track today?"). Today's is skipped if the time has passed or nothing is left to log (`needsQuickLog`); later days are added as long as any target is active and get re-checked on the next refresh. If nothing is left, an already-delivered end-of-day notification is cleared too.
- **When it rebuilds**: launch and every return to the foreground; whenever the count of active targets or targets left to log changes (a signature watched in `ContentView`, so logging, undoing, archiving or adding a target needs no extra calls); a significant time change (midnight/time zone) while the app is open; and edits in the Alerts screens (immediately for toggles/add/delete, after a short pause for typing or the time picker, and when leaving an edit screen).
- **Permission**: requested the first time a reminder is on and iOS hasn't been asked; if denied, the Alerts screen shows a note with an "Open iOS Settings" button.
- **Tapping an alert**: `NotificationRouter` (shared, held statically since iOS keeps only a weak delegate) sets a flag for morning/evening alerts. `ContentView` sees it, switches to Home, clears Home's pushed screens and opens the Quick update sheet. Custom alerts just open the app. No banners are shown while the app is open.
- **Limits**: the evening alert stops after 14 days without opening the app (morning/custom keep going). If another sheet is already open when an alert is tapped, the tap just opens the app. 64 pending-notification cap (evening uses up to 14). Free Apple ID builds expiring also stops alerts.

## UI Layer
- `ContentView`: TabView (Home / Calendar / History / Settings) with a selection binding; tapping Home while on Home clears its navigation path; Home keeps its place when you switch tabs. It owns the Quick update sheet, so it can open from any tab (the Home banner calls an `openFocus` closure) and reacts to `NotificationRouter`.
- `HomeView`: 2x2 `AreaCard`s showing area name, the count of active targets, and a status tint (no progress ring); "Today's focus" banner opens Quick update; profile button opens a placeholder. Owns navigation destinations for `Area`, `Item`, `Target`.
- `AreaPagerView`: horizontal pager across the 4 areas, status dots, "+" menu (New item / New target; New target is disabled when the area has no items). After saving a new item it offers a "Set a target?" alert.
- `AreaDetailView`: no body map (removed for now). Targets as a 3-across grid of `TargetGridCard` (name, short details, last six periods as dots, tinted by status); tapping opens the item page. Long-press menu: Mark done (binary targets) or Log now… (all others), Archive target, Archive item, Delete target, Delete item. Below: "Items without a target" (only shown if any). Not a `List`, so no swipe actions.
- `ItemSummaryView`: current target, Upcoming and Previous targets strips (long-press: Archive / Delete), "Edit item" (opens `AddItemView(editing:)`), "New target".
- `AddItemView`: create or edit. Edit adds Priority and Archive; changing measurement fields on an item that already has targets asks for confirmation. Area is read-only. Dropdown subarea picker with "New subarea...". Amount items get a Unit menu (built-in units, custom units, "New unit…"). Creating an item saves it immediately, so the New target form opened right after ("Create target") starts with a settled item (before this, the form could reset a few seconds in).
- `AddTargetView`: create or edit. In edit mode: end date/duration is always editable (never earlier than the last logged day); frequency and goal are locked once the target has logs (a "Start a new target from this one" button opens a pre-filled new target); start date is always fixed. New time targets default to a 30-minute tolerance.
- `TargetDetailView`: header, scrolling period rows (tap a past/current one to open its logs), stats placeholder pinned at the bottom, "+ Log" (only while the target is active) and Edit buttons. `PeriodLogsView` lists a period's logs (tap to edit, swipe to delete, + to add or backdate); `LogEditorView` handles the form (time targets pick a clock time; an early-morning time on an evening goal is stamped on the next calendar day).
- `LogNowView`: a sheet that logs one target right now whatever its state (a cap, an already-met target, an NFC target logged manually). Same inputs as Quick update, plus a Log button; the timer clears after logging. Reached from the long-press menu and the target page.
- `QuickInputView`: stack of cards for active targets that `needsQuickLog` (caps and NFC excluded; the empty state points to Log now). Swipe right logs, left skips to the back; check / amount / duration / timer (typed minutes plus start-pause timer, summed) / time cards from `TargetLogInputs`; undo bar after a log. Targets logged this visit don't come straight back.
- `CalendarView`: month/week toggle; filter pills for Area, Subarea (only once an area is picked) and Status. Day tints: green = all done, red = all missed, orange = mixed, dark gray = open, light gray = future. A one-day period colors its day; a longer period colors only the day it was settled (and its last day while open). Week rows use the whole-period view. Filtered periods are computed once per update and shared.
- `PlanView` (the Weekly Plan, in the Calendar tab): pick a weekday and see that day's slots on a 24-hour timeline (scrolls to about 5 AM). Each slot is a `PlanEntry`, weekly or one-off. + adds one (new slots default to "Just this day" for the date shown; "Every week" gives weekday buttons), tap edits (a slot can switch between the two), long-press deletes; overlapping slots sit side by side. The date bar with week arrows (up to 52 weeks ahead) is always shown so one-offs on later weeks are reachable; after saving a one-off the view jumps to its date. With calendar access allowed, `CalendarEventsStore` shows that date's events as faint bands behind the slots and all-day events as chips, with a Calendars menu to hide calendars, and a slot overlapping an event gets an orange outline plus a warning line. Events are read-only and affect nothing else (no effect on status, logging, History or alerts); plan slots aren't connected to logs. Slots whose item is archived are hidden.
- `HistoryView`: static summary cards and locked badge grid (placeholder).
- `SettingsView`: Alerts, Notes, Appearance (System/Light/Dark), Subareas, Units, Archived, and "Delete all data…" at the bottom. Delete all asks you to type DELETE, then removes every record (logs, targets, items, subareas, notes, reminders, custom units, plan entries, children first), re-seeds the built-in subareas and default (off) alerts, and rebuilds notifications; it keeps the appearance setting. It first calls `resetNavigation` (clears Home's pushed screens so none holds a deleted model). Its list of models is hand-written and must match the schema in `FerbApp.swift`. There's no backup, so it can't be undone. It doesn't end a Live Activity banner left on the lock screen.
- `ArchivedView`: archived items and targets with Restore. Archiving an item hides its targets without flagging them.

## Entry Points
- App launch -> `FerbApp` -> `ContentView` (TabView) -> Home first.
- Tapping a start-of-day or end-of-day notification -> `NotificationRouter` -> `ContentView` -> Home with Quick update open.

## Configuration & Environment
- No `.env` or secrets. Local SwiftData storage, `isStoredInMemoryOnly: false`. No CloudKit yet. Free Apple ID builds expire after 7 days (re-run from Xcode to renew; keeps data).
- The bundle identifier is still `com.duncanbagley.FirstApp` (kept on purpose after the rename so on-device data and the notification permission carry over; changing it makes iOS treat it as a new app). Target, scheme and app name are Ferb.
- Schema changes that add defaulted fields (or a whole new model, like `Reminder`) migrate automatically. **Exception:** a new non-optional enum field with a default (like `TimeDirection` was) is not filled in on existing rows and crashes when read ("Could not cast value of type Optional<Any> to …"; it happened on the phone, not in the simulator, which has no old rows). Store such fields as optional with a computed wrapper (`timeDirectionStored` + `timeDirection`; `@Attribute(originalName:)` keeps old values). New optional fields (like `PlanEntry.date`) are safe. Changes like turning a field into a different type require deleting the app (this happened once: Subarea enum -> model). The container creation `fatalError`s if migration fails.
- Build setting: default actor isolation is MainActor (Swift 5 mode). Plain types used off the main actor are marked `nonisolated` to avoid Swift 6 isolation warnings (`LogInputKind`, the app's `FerbTimerAttributes` and its `ContentState`); apply the same to any other plain enum that warns on `==`.
- **Live Activity setup**: the Ferb target's Info needs `Supports Live Activities` (`NSSupportsLiveActivities`) = YES. The widget extension target is `FerbTimerWidget` (iOS 17, bundle ID `com.duncanbagley.FirstApp.FerbTimerWidget`) and has its own signing. Live Activities also need to be allowed for Ferb in iOS Settings (on by default). The calendar permission string (full calendar access, needed to read events) is in the Ferb target's Info.

## Notable Patterns / Conventions
- **Items are definitions, targets are actions**: cadence, logs and status live on `Target`.
- **Everything is derived from logs**: status, periods, settled days, calendar colors. Nothing is cached or stored.
- **Create and delete logs only through `target.record` / `target.remove`.**
- **One logging path**: Quick update and Log now both use `TargetLogInputs` + `LogDraft`; "still needs logging" is only defined in `needsQuickLog`.
- **Notifications are rebuilt, not patched**: always clear-and-re-add from saved settings.
- **Archived** = hidden everywhere (counts, grid, calendar, pickers) but kept; `isActive` returns false for hidden targets, so most screens exclude them automatically.
- **Filtering happens in Swift, not SwiftData predicates** (`@Query` fetches, small data), except the archived pickers.
- **Edit rules protect history**: frequency, start and goal can't change once a target has logs.
- Proposals before changes: Duncan wants one change at a time with pros and cons explained first.
- **Live Activity**: `FerbTimerAttributes` exists twice (widget file and `TimerActivityAttributes.swift`); the type name, property names and types must stay identical or the banner silently stops working, so change both together. Only one timer banner shows at a time (starting or resuming replaces another's); pausing updates only its own banner. The key linking a target to its banner is the base64 of its JSON-encoded `persistentModelID` with sorted keys (unsorted keys made pause fail to find the banner). iOS ends a Live Activity after roughly 12 hours; the next resume starts a new one. No pause/resume buttons on the lock screen yet (that would need App Intents).
- **Delete all data keeps a hand-written model list**: when adding a model, add it to the schema and to `deleteAllData()`.

## Recent Changes
- 2026-11-01: Swift 6 warning cleanup. `CalendarEventsStore.swift` (observer closure rebinds `self` with `guard let self` before the `Task`), `TargetLogInput.swift` (`LogInputKind` is `nonisolated`), `TimerActivityAttributes.swift` (`FerbTimerAttributes` and `ContentState` are `nonisolated`; the widget's copy is unchanged).

## Open Items / Ideas
- Duncan confirmed (2026-11-01) the earlier device checks are fixed (timer crash, Live Activity pause/resume, one-off plan slots, Delete all data, alerts, Log now). Still worth a quick device check after the warning cleanup: Live Activity (start, pause, resume, log) and the Weekly Plan event bands refreshing when the Calendar app changes.
- A bedtime goal set after midnight (before noon) counts as a morning goal: logs aren't attributed across midnight.
- No export or backup (data lives only on the phone). This is the biggest risk, and a prerequisite for ever changing the bundle identifier.
- History tab, Profile sheet, stats block on the target page and real NFC are placeholders (there's no NFC UI now; NFC-method items are logged manually via Log now).
- Alerts: no banners while the app is open (small optional addition); custom alerts don't route anywhere; the evening window runs out after 14 days unopened.
- Nothing rolls a target over when its window ends.
- No pull-to-refresh; the screens themselves aren't refreshed at midnight while the app stays open (only the notifications are).
- Pending renames: binary subtypes to success/avoidance, quantity direction to maximum/minimum.
- Items can be deleted only from the area list's long-press menu (not from the item page).
- Body map pages were removed as too clunky; Duncan wants them back later.
- Reward is an unused placeholder String on `Target`.
- Possible rename: `TargetRow.swift` now holds `TargetGridCard` and helpers (renaming is safe: synchronized folders).
- Possible follow-ups: end the Live Activity banner when Delete all data runs (and clean up banners orphaned after a crash or force-quit); a small badge to tell one-off from weekly slots on the plan timeline; lock-screen pause/resume buttons; custom subareas and units are inserted but not saved right away in the item form (same one-line fix as the item itself if they ever misbehave).
