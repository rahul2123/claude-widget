# UI Revamp Design — Claude Usage Monitor

**Date:** 2026-06-12  
**Scope:** Aesthetic overhaul + settings panel + refresh interval + usage history sparkline + threshold alerts

---

## Goals

1. **Refined dark aesthetic** — tighter spacing, gradient-glow progress bars, better type hierarchy
2. **Settings panel** — dedicated ⚙ overlay replacing inline pin selector and About view
3. **Refresh interval** — user-selectable 1–5 min cadence (default 5), persisted in UserDefaults
4. **Usage history sparkline** — 5-hour window tracked over time, displayed inline on main panel
5. **Threshold alerts** — macOS notification when any window crosses user-set threshold

---

## Panel Structure

### Main view

```
┌──────────────────────────────────────────┐
│  ● Claude Usage                    ↺  ⚙  │  ← header
├──────────────────────────────────────────┤
│  5-hour                            42%   │
│  ████████░░░░░░░░░░░░  resets in 2h 14m  │
│  Week                              67%   │
│  █████████████░░░░░░░  resets in 3d 7h   │
│  Sonnet                            88%   │
│  ████████████████████  resets in 3d 7h   │
├──────────────────────────────────────────┤
│  5-hour · today                          │
│  ╭────────────────────────────────╮      │  ← sparkline
│  │  ∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿          │      │
│  ╰────────────────────────────────╯      │
├──────────────────────────────────────────┤
│  ↺ every 5m · 14:32    Widget    Quit   │  ← footer
└──────────────────────────────────────────┘
```

Panel width: 320px (up from 300px). Dark background `#1c1c1e` throughout.

### Settings overlay (⚙ tap)

```
┌──────────────────────────────────────────┐
│  ‹  Settings                             │
├──────────────────────────────────────────┤
│  MENU BAR LABEL                          │
│  [5h] [Week] [Sonnet] [Highest] [5h+Wk] │
│                                          │
│  REFRESH EVERY                           │
│  [1m] [2m] [3m] [4m] [5m]               │
│                                          │
│  ALERT WHEN USAGE EXCEEDS                │
│  [Off] [70%] [80%] [90%]                │
│                                          │
│  Desktop widget          ● (toggle)      │
├──────────────────────────────────────────┤
│  com.claudeusagewidget.app    Quit       │
└──────────────────────────────────────────┘
```

`‹` back arrow returns to main view. No separate About/info button — token expiry and account type removed (rarely needed; keychain status visible via error messages).

---

## Visual Design

### Progress bars
- Height: 6px (up from 8px), `border-radius: 3px`
- Fill: left-to-right gradient, dark anchor → bright tip
  - Green: `#1a7a35 → #34c759`, glow `box-shadow: 0 0 6px #34c75966`
  - Amber: `#7a4a00 → #ff9f0a`, glow `0 0 6px #ff9f0a55`
  - Orange: `#7a3000 → #ff6b00`, glow `0 0 6px #ff6b0055`
  - Red: `#7a1a16 → #ff453a`, glow `0 0 6px #ff453a55`
- Track: `#2c2c2e`

### Typography
- Row label: `11px`, color `#aeaeb2`
- Percentage: `11px semibold`, color = usage color
- Reset time / secondary: `9px`, color `#48484a`
- Section headers (settings): `9px uppercase`, letter-spacing `0.6px`, color `#636366`
- Footer: `9px`, color `#48484a`

### Sparkline
- Inline SVG, full panel width, height 28px
- Stroke: `#34c759` (5-hour color), `stroke-width: 1.5`, `opacity: 0.8`
- Background pill: `#2c2c2e`, `border-radius: 6px`, padding `7px 8px`
- Label: `"5-hour · today"` in `9px #636366`

### Section separators
- `#2c2c2e` 1px horizontal lines (replaces SwiftUI `Divider`)

### Pill buttons (settings)
- Selected: `background #0a84ff`, `font-weight 600`, white text
- Unselected: `background #2c2c2e`, `color #8e8e93`
- `border-radius: 5px`, padding `4px 7–8px`, `font-size: 10px`

### Desktop widget
- Same gradient bars, same color palette, same typography scale applied

---

## Menu Bar Label

### `PinnedWindow` cases

| Case | Display |
|---|---|
| `.hour` | `42%` in usage color |
| `.week` | `67%` in usage color |
| `.sonnet` | `88%` in usage color |
| `.highest` | highest % across all windows |
| `.bothHourWeek` (new) | `42% / 67%` — 5h color · gray slash · week color |

`.bothHourWeek` renders two `Text` spans with a gray `/` separator. No label text — colors distinguish which is which.

---

## Data Layer

### `UsageHistoryStore.swift` (new)

```swift
struct HistoryPoint: Codable {
    let timestamp: Date
    let hourPct: Double
}

class UsageHistoryStore {
    static let shared = UsageHistoryStore()
    private static let key = "usageHistoryPoints"
    private static let maxPoints = 100  // ~8h at 5min

    private(set) var points: [HistoryPoint] = []

    func append(hourPct: Double) { ... }  // prunes oldest when > maxPoints, persists
    func load() { ... }                  // called from UsageService.init
}
```

`append` is called by `UsageService` after every successful API response.

### `AlertService.swift` (new)

```swift
struct AlertService {
    // alerted: tracks windows currently above threshold (prevents repeat notifications)
    // key: window identifier ("hour", "week", "sonnet")
    // clears when window drops 5% below threshold
    static func check(stats: UsageStats, threshold: Int, alerted: inout Set<String>)
}
```

- Threshold `0` = disabled (no check)
- Fires `UNUserNotification` for any window crossing threshold from below
- Requests `UNUserNotificationCenter` authorization on first fire (if not already granted)
- Notification body: `"[Window] usage at [N]% — resets [time]"`

### `UsageService.swift` additions

```swift
@Published var refreshMinutes: Int {
    didSet {
        UserDefaults.standard.set(refreshMinutes, forKey: "refreshIntervalMinutes")
        restartTimer()  // invalidate + reschedule, no immediate refetch
    }
}

@Published var alertThreshold: Int {
    didSet { UserDefaults.standard.set(alertThreshold, forKey: "alertThreshold") }
}
```

- `refreshMinutes` init: `UserDefaults.standard.integer(forKey:) ?? 5`
- `alertThreshold` init: `UserDefaults.standard.integer(forKey:)` (0 if unset = off)
- `restartTimer()`: invalidates existing timer, schedules new one at `Double(refreshMinutes * 60)`
- `startFetching()` replaced by `restartTimer()` + initial `fetchUsage()` call

### New UserDefaults keys

| Key | Type | Default |
|---|---|---|
| `refreshIntervalMinutes` | Int | 5 |
| `alertThreshold` | Int | 0 (off) |
| `usageHistoryPoints` | Data (JSON-encoded) | [] |
| `pinnedWindow` | String | existing |

---

## Files Changed

| File | Type | Summary |
|---|---|---|
| `MenuBarView.swift` | Major revamp | New `SettingsView`, `SparklineView`, gradient bars, updated footer, remove `PinSelectorView` + `AboutView` |
| `App.swift` | Update | `MenuBarLabel` dual-display for `.bothHourWeek`, add case to `PinnedWindow` |
| `Models.swift` | Update | Add `PinnedWindow.bothHourWeek` case and `label` string |
| `UsageService.swift` | Update | Add `refreshMinutes`, `alertThreshold`, `restartTimer()`, call history + alert after fetch |
| `DesktopWidget.swift` | Visual refresh | Gradient bars, updated palette, font sizes |
| `UsageHistoryStore.swift` | New | 100-point rolling history, UserDefaults persistence |
| `AlertService.swift` | New | Threshold check, debounce set, UNUserNotification |

Total: 5 modified, 2 new Swift files. No new dependencies beyond `UserNotifications` framework (add to `swiftc` compile flags).

---

## Build Change

Add `-framework UserNotifications` to the `swiftc` compile command in `CLAUDE.md` and `README.md`.

---

## Error / Edge Cases

- **History empty on first launch**: sparkline renders nothing (empty SVG path) — no crash
- **Alert permission denied**: `AlertService.check` silently no-ops if authorization not granted
- **Re-alert debounce**: once alerted for a window, suppress until that window drops ≥5% below threshold
- **Timer restart**: changing `refreshMinutes` reschedules from now, does not trigger an immediate fetch
- **`.bothHourWeek` with missing data**: if either window unavailable, falls back to showing `—`
