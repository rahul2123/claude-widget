# Quick-Wins Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three small features to the Claude Usage Monitor menu bar app — a live (1-min ticking) reset countdown, a launch-at-login toggle, and an Opus weekly usage row.

**Architecture:** Opus row threads a new `UsageStats.opusWeek` field from the already-decoded `seven_day_opus` API field into a conditionally-shown `WindowRow`. The live countdown wraps the window rows in a `TimelineView(.periodic)` and parameterizes the time used for formatting. Launch-at-login is a thin `SMAppService.mainApp` wrapper driven by a settings toggle whose source of truth is the OS registration status.

**Tech Stack:** Swift, SwiftUI, AppKit, ServiceManagement (new), `swiftc` direct compile (no Xcode, no SPM). Tests are a standalone `swiftc -parse-as-library` binary.

**Spec:** `docs/superpowers/specs/2026-06-13-quick-wins-batch-design.md`

---

## Build & Test Commands (reference)

**App compile** (note the new `-framework ServiceManagement`):
```bash
swiftc ClaudeUsageWidget/*.swift \
  -o bin/ClaudeUsageWidget \
  -framework SwiftUI -framework AppKit -framework Security \
  -framework UserNotifications -framework ServiceManagement \
  -target arm64-apple-macos13.0
```

**Bundle:** `./build.sh`  → produces `build/Claude Usage Monitor.app`

**Tests:** `bash Tests/run_tests.sh`  → expect `Results: N passed, 0 failed` / `PASS`
(The test target does NOT compile `MenuBarView.swift`, `App.swift`, or `LoginItemService.swift`, so it needs no SwiftUI/ServiceManagement frameworks.)

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `ClaudeUsageWidget/Models.swift` | API shape → display models | Add `UsageStats.opusWeek`, parse `seven_day_opus`, default param on memberwise init |
| `ClaudeUsageWidget/LoginItemService.swift` (new) | OS login-item registration | New `SMAppService.mainApp` wrapper |
| `ClaudeUsageWidget/MenuBarView.swift` | Dropdown UI | Opus row, TimelineView countdown, login-item toggle |
| `Tests/AlertTests.swift` | CLI test binary | Add Opus parsing tests + register in `main` |
| `CLAUDE.md` | Build docs | Add `-framework ServiceManagement` to compile command |

---

## Task 1: Opus weekly row

Adds the Opus field to the model (test-first), then the conditional UI row.

**Files:**
- Modify: `ClaudeUsageWidget/Models.swift:68-87` (`UsageStats`)
- Modify: `Tests/AlertTests.swift` (new test function + registration)
- Modify: `ClaudeUsageWidget/MenuBarView.swift:82-87` (`UsageContentView`)

- [ ] **Step 1: Write the failing Opus parsing test**

Add this function to `Tests/AlertTests.swift` immediately after `testAlertWindow()` (after line 68):

```swift
// MARK: - Opus parsing

func testOpusParsing() {
    section("Opus parsing") {
        let jsonPresent = """
        {
          "five_hour": {"utilization": 10.0, "resets_at": null},
          "seven_day": {"utilization": 20.0, "resets_at": null},
          "seven_day_sonnet": {"utilization": 30.0, "resets_at": null},
          "seven_day_opus": {"utilization": 42.0, "resets_at": null}
        }
        """
        let resp = try! JSONDecoder().decode(
            UsageResponse.self, from: jsonPresent.data(using: .utf8)!)
        let stats = UsageStats(from: resp, lastUpdated: Date())
        expect(stats.opusWeek.available, "opus available when present")
        expectEqual(stats.opusWeek.pct, 42.0, "opus pct == 42")

        let jsonNull = """
        {
          "five_hour": {"utilization": 10.0, "resets_at": null},
          "seven_day": {"utilization": 20.0, "resets_at": null},
          "seven_day_sonnet": {"utilization": 30.0, "resets_at": null},
          "seven_day_opus": null
        }
        """
        let respNull = try! JSONDecoder().decode(
            UsageResponse.self, from: jsonNull.data(using: .utf8)!)
        let statsNull = UsageStats(from: respNull, lastUpdated: Date())
        expect(!statsNull.opusWeek.available, "opus unavailable when null")
    }
}
```

Register it in `@main struct TestRunner` (`Tests/AlertTests.swift:366`), right after `testAlertWindow()`:

```swift
        testAlertWindow()
        testOpusParsing()
        testUsageAlert()
```

- [ ] **Step 2: Run tests to verify the new one fails (compile error)**

Run: `bash Tests/run_tests.sh`
Expected: FAIL — compile error `value of type 'UsageStats' has no member 'opusWeek'`. (Red state: the member does not exist yet.)

- [ ] **Step 3: Add `opusWeek` to `UsageStats`**

In `ClaudeUsageWidget/Models.swift`, replace the entire `struct UsageStats { … }` (lines 68-87) with:

```swift
struct UsageStats {
    let hour: WindowStat        // five_hour
    let week: WindowStat        // seven_day
    let sonnetWeek: WindowStat  // seven_day_sonnet
    let opusWeek: WindowStat    // seven_day_opus
    let lastUpdated: Date

    init(from response: UsageResponse, lastUpdated: Date) {
        self.hour = WindowStat(from: response.five_hour)
        self.week = WindowStat(from: response.seven_day)
        self.sonnetWeek = WindowStat(from: response.seven_day_sonnet)
        self.opusWeek = WindowStat(from: response.seven_day_opus)
        self.lastUpdated = lastUpdated
    }

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

The `opusWeek: WindowStat = .unavailable` default keeps the existing `makeStats` helper (`Tests/AlertTests.swift:40-48`) and any other memberwise call sites compiling unchanged.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash Tests/run_tests.sh`
Expected: PASS — `Results: 86 passed, 0 failed` (83 existing + 3 new Opus assertions).

- [ ] **Step 5: Add the Opus UI row**

In `ClaudeUsageWidget/MenuBarView.swift`, in `UsageContentView` (lines 82-87), replace:

```swift
        } else if let stats = service.stats {
            VStack(spacing: 12) {
                WindowRow(title: "5-hour", stat: stats.hour)
                WindowRow(title: "Week", stat: stats.week)
                WindowRow(title: "Sonnet (week)", stat: stats.sonnetWeek)
            }
```

with:

```swift
        } else if let stats = service.stats {
            VStack(spacing: 12) {
                WindowRow(title: "5-hour", stat: stats.hour)
                WindowRow(title: "Week", stat: stats.week)
                WindowRow(title: "Sonnet (week)", stat: stats.sonnetWeek)
                if stats.opusWeek.available {
                    WindowRow(title: "Opus (week)", stat: stats.opusWeek)
                }
            }
```

(Task 2 changes these `WindowRow(...)` calls again to add a `now:` argument — that is fine, this row gets the same treatment there.)

- [ ] **Step 6: Verify app compiles**

Run:
```bash
swiftc ClaudeUsageWidget/*.swift -o bin/ClaudeUsageWidget \
  -framework SwiftUI -framework AppKit -framework Security \
  -framework UserNotifications -framework ServiceManagement \
  -target arm64-apple-macos13.0
```
Expected: exits 0, no errors. (`ServiceManagement` is harmless here even though it's unused until Task 3.)

- [ ] **Step 7: Commit**

```bash
git add ClaudeUsageWidget/Models.swift ClaudeUsageWidget/MenuBarView.swift Tests/AlertTests.swift
git commit -m "feat: Opus weekly row — parse seven_day_opus, show row when available"
```

---

## Task 2: Live reset countdown

Parameterize the countdown formatter on a `now` time, then drive re-renders every 60s with `TimelineView`.

**Files:**
- Modify: `ClaudeUsageWidget/MenuBarView.swift` — `UsageContentView` (lines 76-99), `WindowRow` (lines 121-169)

- [ ] **Step 1: Add a `now` property to `WindowRow` and use it in `resetText`**

In `ClaudeUsageWidget/MenuBarView.swift`, change the `WindowRow` stored properties (lines 122-123) from:

```swift
struct WindowRow: View {
    let title: String
    let stat: WindowStat
```

to:

```swift
struct WindowRow: View {
    let title: String
    let stat: WindowStat
    var now: Date = Date()
```

Then change the reset-text call site inside `body` (line 146) from:

```swift
                Text("resets \(resetText(reset))")
```

to:

```swift
                Text("resets \(resetText(reset, now: now))")
```

And replace the `resetText` method (lines 157-168) with:

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

The default `var now: Date = Date()` means any `WindowRow(...)` call without a `now:` argument still compiles and behaves exactly as before (static snapshot at render).

- [ ] **Step 2: Wrap the rows in a `TimelineView` and thread the tick date in**

In `ClaudeUsageWidget/MenuBarView.swift`, in `UsageContentView` (the `else if let stats = service.stats` branch, as edited in Task 1), replace:

```swift
        } else if let stats = service.stats {
            VStack(spacing: 12) {
                WindowRow(title: "5-hour", stat: stats.hour)
                WindowRow(title: "Week", stat: stats.week)
                WindowRow(title: "Sonnet (week)", stat: stats.sonnetWeek)
                if stats.opusWeek.available {
                    WindowRow(title: "Opus (week)", stat: stats.opusWeek)
                }
            }
```

with:

```swift
        } else if let stats = service.stats {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(spacing: 12) {
                    WindowRow(title: "5-hour", stat: stats.hour, now: context.date)
                    WindowRow(title: "Week", stat: stats.week, now: context.date)
                    WindowRow(title: "Sonnet (week)", stat: stats.sonnetWeek, now: context.date)
                    if stats.opusWeek.available {
                        WindowRow(title: "Opus (week)", stat: stats.opusWeek, now: context.date)
                    }
                }
            }
```

`TimelineView(.periodic(from: .now, by: 60))` re-evaluates its body every 60 seconds while visible and passes the current `context.date`, so each `WindowRow` recomputes its countdown against a fresh `now`. It pauses automatically when the menu closes.

- [ ] **Step 3: Verify app compiles**

Run:
```bash
swiftc ClaudeUsageWidget/*.swift -o bin/ClaudeUsageWidget \
  -framework SwiftUI -framework AppKit -framework Security \
  -framework UserNotifications -framework ServiceManagement \
  -target arm64-apple-macos13.0
```
Expected: exits 0, no errors.

- [ ] **Step 4: Run tests to confirm nothing broke**

Run: `bash Tests/run_tests.sh`
Expected: PASS — `Results: 86 passed, 0 failed` (unchanged; `MenuBarView.swift` is not in the test target, but confirm the model layer is still green).

- [ ] **Step 5: Commit**

```bash
git add ClaudeUsageWidget/MenuBarView.swift
git commit -m "feat: live reset countdown — TimelineView 1-min tick, now-param resetText"
```

---

## Task 3: Launch at login

New `SMAppService` wrapper plus a settings toggle whose state reflects the OS registration.

**Files:**
- Create: `ClaudeUsageWidget/LoginItemService.swift`
- Modify: `ClaudeUsageWidget/MenuBarView.swift` — `SettingsView` (add toggle row near the Desktop-widget toggle, lines 326-342)
- Modify: `CLAUDE.md` — add framework to documented compile command

- [ ] **Step 1: Create `LoginItemService.swift`**

Create `ClaudeUsageWidget/LoginItemService.swift` with:

```swift
import Foundation
import ServiceManagement

/// Thin wrapper over the OS login-item registration. The source of truth is
/// `SMAppService.mainApp.status` (the OS owns it) — never mirrored to UserDefaults.
enum LoginItemService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log("⚙️ login item \(on ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
    }

    private static func log(_ message: String) {
        let logFile = "/tmp/claude-usage-widget.log"
        let timestamp = DateFormatter.localizedString(
            from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)\n"
        if let handle = FileHandle(forWritingAtPath: logFile) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(toFile: logFile, atomically: true, encoding: .utf8)
        }
    }
}
```

(The `log` helper mirrors the existing private logger in `UsageService.swift:180-191` — same file, same no-tokens convention. Kept local because `UsageService.log` is private.)

- [ ] **Step 2: Add the toggle row to `SettingsView`**

In `ClaudeUsageWidget/MenuBarView.swift`, in `SettingsView.body`, immediately before the existing Desktop-widget `HStack` (line 326, the `HStack { VStack(alignment: .leading, spacing: 2) { Text("Desktop widget") …`), insert:

```swift
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login")
                        .font(.system(size: 11))
                    Text("Start automatically when you log in")
                        .font(.system(size: 9))
                        .foregroundColor(Color(red: 0.388, green: 0.388, blue: 0.400))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { LoginItemService.isEnabled },
                    set: { LoginItemService.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8)
            }
```

This matches the Desktop-widget toggle styling exactly. The binding reads `SMAppService.status` on get and registers/unregisters on set.

- [ ] **Step 3: Verify app compiles (with ServiceManagement now in use)**

Run:
```bash
swiftc ClaudeUsageWidget/*.swift -o bin/ClaudeUsageWidget \
  -framework SwiftUI -framework AppKit -framework Security \
  -framework UserNotifications -framework ServiceManagement \
  -target arm64-apple-macos13.0
```
Expected: exits 0, no errors.

- [ ] **Step 4: Update the documented compile command in `CLAUDE.md`**

In `CLAUDE.md`, in the `## Build` section, change the compile command's framework line from:

```bash
  -framework SwiftUI -framework AppKit -framework Security -framework UserNotifications \
```

to:

```bash
  -framework SwiftUI -framework AppKit -framework Security -framework UserNotifications -framework ServiceManagement \
```

- [ ] **Step 5: Commit**

```bash
git add ClaudeUsageWidget/LoginItemService.swift ClaudeUsageWidget/MenuBarView.swift CLAUDE.md
git commit -m "feat: launch-at-login toggle via SMAppService"
```

---

## Task 4: Build, bundle, and manual QA

Assemble the real app bundle and verify the two UI/OS features that cannot be unit-tested.

**Files:** none (build + verification only)

- [ ] **Step 1: Full test run**

Run: `bash Tests/run_tests.sh`
Expected: PASS — `Results: 86 passed, 0 failed`.

- [ ] **Step 2: Compile + bundle**

Run:
```bash
swiftc ClaudeUsageWidget/*.swift -o bin/ClaudeUsageWidget \
  -framework SwiftUI -framework AppKit -framework Security \
  -framework UserNotifications -framework ServiceManagement \
  -target arm64-apple-macos13.0
./build.sh
```
Expected: both exit 0; `build/Claude Usage Monitor.app` produced and signed.

- [ ] **Step 3: Launch**

Run: `open 'build/Claude Usage Monitor.app'`
Expected: menu bar icon appears; clicking it opens the dropdown.

- [ ] **Step 4: Manual QA — Opus row**

- If the account has Opus weekly data: confirm an "Opus (week)" row appears under "Sonnet (week)" with a percentage and bar.
- If the account has no Opus data (`seven_day_opus` null): confirm NO Opus row appears (no empty/"not available" placeholder).

- [ ] **Step 5: Manual QA — live countdown**

- Open the dropdown and leave it open across a minute boundary.
- Confirm a "resets in Xh Ym" line decrements (e.g. `in 2h 14m` → `in 2h 13m`) WITHOUT closing/reopening the menu or a data refresh.

- [ ] **Step 6: Manual QA — launch at login**

- Open Settings (gear icon). Toggle "Launch at login" ON.
- Open System Settings → General → Login Items; confirm "Claude Usage Monitor" is listed under "Open at Login".
- Toggle OFF in the app; confirm it disappears from Login Items.
- Reopen the app's Settings; confirm the toggle reflects the current OS state.

- [ ] **Step 7: Commit (only if build artifacts are tracked; otherwise skip)**

```bash
git status   # check whether bin/ or build/ are tracked
# If bin/ClaudeUsageWidget is tracked and changed:
git add bin/ClaudeUsageWidget
git commit -m "build: rebuild binary with quick-wins batch"
```
(If `bin/`/`build/` are gitignored, no commit — manual QA is the deliverable for this task.)

---

## Notes for the implementer

- **SourceKit false positives:** editor "Cannot find type in scope" diagnostics across files are expected — SourceKit analyzes files individually; `swiftc` compiles them together. Trust the `swiftc` compile result, not the editor.
- **Never add `Co-Authored-By` trailers** to commits (project rule).
- The test target compiles only `Models.swift`, `AlertValidation.swift`, `AlertService.swift`, `AlertTests.swift` — do not add `MenuBarView.swift` or `LoginItemService.swift` to `Tests/run_tests.sh`.
