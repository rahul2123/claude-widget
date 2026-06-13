# Quick-Wins Batch — Design Spec

**Date:** 2026-06-13
**Status:** Approved

Three small, low-risk features for the Claude Usage Monitor menu bar app, batched because they touch overlapping files (`Models.swift`, `MenuBarView.swift`) and carry no shared architectural risk.

> Note: a fourth candidate — configurable refresh interval — was dropped. It already ships (`UsageService.refreshMinutes`, persisted, restarts timer; settings "Refresh every" pills 1–5 min).

---

## Feature 1 — Live reset countdown

### Problem
`WindowRow` already renders `resets in 2h 14m`, but the text is computed once at render time (`Date()` in `resetText`). It only refreshes when usage data is re-fetched or the menu is reopened. While the menu sits open, the countdown is stale.

### Design
Wrap the window rows in a `TimelineView(.periodic(from: .now, by: 60))` so SwiftUI re-renders them every 60 seconds while the menu is open. `TimelineView` auto-pauses when the view is offscreen — no manual `Timer`, no leak, no teardown.

`WindowRow.resetText` changes from reading `Date()` internally to taking the current time as a parameter:

```swift
private func resetText(_ date: Date, now: Date) -> String {
    let interval = date.timeIntervalSince(now)
    guard interval > 0 else { return "now" }
    if interval < 86_400 {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return h > 0 ? "in \(h)h \(m)m" : "in \(m)m"
    }
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM d"
    return fmt.string(from: date)
}
```

`WindowRow` gains a `now: Date` property, threaded from the TimelineView context date in `UsageContentView`.

### Scope
- `MenuBarView.swift` only.
- 1-minute cadence matches the minute-granular text; per-second ticking would be wasted redraws (decided during brainstorming).
- Menu rows only — **not** the menu bar label (decided during brainstorming).

---

## Feature 2 — Launch at login

### Problem
No way to have the app start automatically at login. Expected for a menu bar utility.

### Design
New file `LoginItemService.swift` wrapping `SMAppService.mainApp` (macOS 13+, target is already 13.0):

```swift
import ServiceManagement

enum LoginItemService {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
        } catch {
            // log via existing /tmp/claude-usage-widget.log convention
        }
    }
}
```

**Source of truth is `SMAppService.status`, not UserDefaults** — the OS owns the registration state. The settings toggle reads `.status` and writes via `register()` / `unregister()`. Default is off (opt-in); a fresh install has no registration.

Settings gets a toggle row mirroring the existing "Desktop widget" toggle styling (title + sub-label + `.switch` toggle, `scaleEffect(0.8)`).

### Scope
- New `LoginItemService.swift`.
- `MenuBarView.swift` — toggle row in `SettingsView`.
- Build: add `-framework ServiceManagement` to the `swiftc` compile command (CLAUDE.md + `build.sh` if it pins frameworks).

### Risk
`SMAppService` keys registration off bundle identity. The persistent signing cert (`Claude Widget Code Signing`) gives a stable identity, so the registration survives rebuilds. Ad-hoc fallback rebuilds may reset it — acceptable for dev.

---

## Feature 3 — Opus weekly row

### Problem
`UsageResponse.seven_day_opus` is decoded but dropped — `UsageStats` exposes only `hour` / `week` / `sonnetWeek`. No Opus row in the menu.

### Design
`Models.swift` — `UsageStats` gains `opusWeek: WindowStat`:

```swift
struct UsageStats {
    let hour: WindowStat
    let week: WindowStat
    let sonnetWeek: WindowStat
    let opusWeek: WindowStat      // seven_day_opus
    let lastUpdated: Date

    init(from response: UsageResponse, lastUpdated: Date) {
        self.hour = WindowStat(from: response.five_hour)
        self.week = WindowStat(from: response.seven_day)
        self.sonnetWeek = WindowStat(from: response.seven_day_sonnet)
        self.opusWeek = WindowStat(from: response.seven_day_opus)
        self.lastUpdated = lastUpdated
    }

    // Memberwise init for tests — opusWeek defaulted so existing call sites compile.
    init(hour: WindowStat, week: WindowStat, sonnetWeek: WindowStat,
         opusWeek: WindowStat = .unavailable, lastUpdated: Date) {
        self.hour = hour
        self.week = week
        self.sonnetWeek = sonnetWeek
        self.opusWeek = opusWeek
        self.lastUpdated = lastUpdated
    }
}
```

The default `opusWeek: WindowStat = .unavailable` keeps existing `Tests/AlertTests.swift` call sites compiling unchanged.

UI — in `UsageContentView`, after the Sonnet row:

```swift
if stats.opusWeek.available {
    WindowRow(title: "Opus (week)", stat: stats.opusWeek, now: now)
}
```

**Show only when available** — hidden entirely when the API returns null (decided during brainstorming). **Not** added to the `PinnedWindow` pin picker (decided during brainstorming).

### Scope
- `Models.swift`, `MenuBarView.swift`.

---

## Testing

| Feature | Test |
|---|---|
| Opus parsing | Extend `Tests/AlertTests.swift`: decode `UsageResponse` JSON with `seven_day_opus` populated → assert `UsageStats.opusWeek.available == true` and pct matches; decode with `seven_day_opus` null → assert `opusWeek.available == false`. Pure, CLI-runnable. |
| Live countdown | Manual QA — open menu, confirm "resets in" decrements each minute without reopening. (`resetText(_:now:)` is pure and could get a unit test for formatting, optional.) |
| Launch at login | Manual QA — toggle on, confirm registration via System Settings → Login Items; relaunch; toggle off; confirm removed. (`SMAppService` needs a real bundle — cannot run in CLI test binary.) |

`Tests/run_tests.sh` continues to pass (83 existing + new Opus tests). Add `Models.swift` is already compiled in the test target; no new framework needed for the Opus test.

---

## Files touched (summary)

| File | Change |
|---|---|
| `Models.swift` | `UsageStats.opusWeek` + parse `seven_day_opus`; memberwise init default param |
| `MenuBarView.swift` | TimelineView wrap + `now`-param countdown; login-item toggle row; Opus row |
| `LoginItemService.swift` (new) | `SMAppService.mainApp` wrapper |
| `Tests/AlertTests.swift` | Opus parsing tests |
| `CLAUDE.md` / `build.sh` | add `-framework ServiceManagement` |

## Out of scope (YAGNI)
- Configurable refresh interval (already exists).
- Per-second countdown ticking.
- Countdown in the menu bar label.
- Opus in the pin picker.
- Login-item state mirrored to UserDefaults.
