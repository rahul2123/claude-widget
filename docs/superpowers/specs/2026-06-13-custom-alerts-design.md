# Custom Usage Alerts — Design

**Date:** 2026-06-13
**Status:** Approved (design)

## Goal

Replace the single global alert threshold (Off / 70 / 80 / 90 %, applied to all
windows) with user-defined alerts. Each alert targets one usage window and a
custom percentage. Up to **3 alerts per window**.

## Scope

- Windows targetable: **5-hour** (`five_hour`) and **Weekly** (`seven_day`) only.
- Per alert: a window + a threshold percentage (5–100 %, 5 % steps).
- Cap: **3 alerts per window** → max 6 alerts total (3 on 5h, 3 on Weekly).
- Empty alert list = alerts off.

### Out of scope (YAGNI)

Custom sounds, per-alert messages, snooze, Sonnet/Opus windows, all-window alerts.

## Data Model — `Models.swift`

```swift
enum AlertWindow: String, Codable, CaseIterable {
    case hour, week
    var label: String { self == .hour ? "5h" : "Wk" }
    var notifLabel: String { self == .hour ? "5-hour" : "Weekly" }
}

struct UsageAlert: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var window: AlertWindow
    var threshold: Int        // 5...100, multiples of 5
}
```

Presence in the list = enabled. Removing a row disables it. The cap is enforced
in the UI, not the model.

## Persistence — `UsageService.swift`

- Remove `@Published var alertThreshold: Int` and `alertKey`.
- Add `@Published var alerts: [UsageAlert]` with `didSet` that JSON-encodes to
  `UserDefaults` under new key `"usageAlerts"`.
- On `init`:
  1. If `"usageAlerts"` exists, decode it.
  2. Else if legacy `"alertThreshold"` > 0, seed `[UsageAlert(window: .week,
     threshold: legacyValue)]` (Weekly is the window most users watch), then
     remove the legacy key.
  3. Else empty list.
- `fetchUsage()` success path calls
  `AlertService.check(stats:, alerts: alerts, alerted: &alertedWindows)`.

## Firing Logic — `AlertService.swift`

New signature:

```swift
static func check(stats: UsageStats, alerts: [UsageAlert], alerted: inout Set<String>)
```

For each alert:
- Resolve the `WindowStat` for its window (`stats.hour` or `stats.week`).
  Skip if `!available`.
- Arm key = `"\(window.rawValue)-\(threshold)"` (finer than today's
  per-window key, so two thresholds on the same window coexist).
- If `stat.pct >= threshold` and key not in `alerted`: insert key, fire.
- Else if `stat.pct < threshold - 5`: remove key (re-arm).

`fire` unchanged in behavior — notification body stays
`"<notifLabel> at <pct>% — resets in …"`, using the alert's `window.notifLabel`.
Notification identifier becomes `"usage-alert-\(window.rawValue)-\(threshold)"`.

## UI — `MenuBarView.swift`

Replace the `settingsSection("Alert when usage exceeds")` pill row with an
`ALERTS` section:

```
ALERTS
  [ 5h | Wk ]   –  80 %  +    ✕      ← one row per alert
  [ 5h | Wk ]   –  95 %  +    ✕
  + Add alert                        ← hidden when 6 total
```

Per-row controls:
- **Window toggle**: 2-segment selector (5h / Wk). Tapping to switch to a
  window that already holds 3 alerts is a no-op (keeps per-window cap).
- **Stepper**: `–` / `+`, range 5–100, step 5, shows `N %`.
- **Remove**: `✕` deletes the row.

Add behavior:
- **Add alert** appends a default alert. Default window = first window with < 3
  alerts (prefer 5h, else Weekly); default threshold = 80.
- Button disabled / hidden when both windows are full (6 total).

Empty list shows only the **Add alert** button (= alerts off).

Reuse existing `settingsSection` and `pillButton` styling; add a small stepper
helper consistent with current pill aesthetic.

## Data Flow (unchanged spine)

```
Timer → fetchUsage() → UsageStats
  → AlertService.check(stats, alerts, &alertedWindows)
    → per matching alert: fire() → UNUserNotificationCenter
MenuBarView edits service.alerts → didSet persists JSON
```

## Testing

No test suite (swiftc direct compile). Manual verification:
- Add 3 alerts on 5h → 4th add for 5h blocked; Weekly still addable.
- Threshold stepper clamps 5–100 in 5 % steps.
- Crossing a threshold fires once; dropping >5 % below re-arms.
- Two thresholds on same window both fire independently.
- Legacy `alertThreshold` migrates to one Weekly alert on first launch.
- Empty list fires nothing.
