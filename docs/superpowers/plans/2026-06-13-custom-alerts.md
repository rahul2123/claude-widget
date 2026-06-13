# Custom Usage Alerts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single global alert threshold with user-defined alerts — up to 3 per window (5h, Weekly), each a window + custom percentage set via a 5%-step stepper (max 6 total).

**Architecture:** A `UsageAlert` value type (window + threshold) is stored as a JSON array in `UserDefaults`. `AlertService` iterates the array, firing/re-arming each alert independently keyed by `window-threshold`. `MenuBarView` renders one editable row per alert with a window toggle, stepper, and remove button, enforcing the per-window cap of 3.

**Tech Stack:** Swift, SwiftUI, AppKit, UserNotifications. No Xcode/SPM/test suite — `swiftc` direct compile only (per CLAUDE.md). Verification per task = successful compile; final task = manual run.

**Spec:** `docs/superpowers/specs/2026-06-13-custom-alerts-design.md`

**Compile command (the "test" for every task):**
```bash
swiftc ClaudeUsageWidget/*.swift \
  -o bin/ClaudeUsageWidget \
  -framework SwiftUI -framework AppKit -framework Security -framework UserNotifications \
  -target arm64-apple-macos13.0
```

**Git:** Never add `Co-Authored-By` trailers (CLAUDE.md).

---

## File Structure

| File | Change |
|---|---|
| `ClaudeUsageWidget/Models.swift` | Add `AlertWindow` enum + `UsageAlert` struct |
| `ClaudeUsageWidget/AlertService.swift` | New `check(stats:alerts:alerted:)` signature; per-alert loop; identifier-keyed `fire` |
| `ClaudeUsageWidget/UsageService.swift` | Replace `alertThreshold: Int` with `alerts: [UsageAlert]`; JSON persistence + legacy migration; update call site + log |
| `ClaudeUsageWidget/MenuBarView.swift` | Replace single-threshold pill row with editable alert rows (toggle + stepper + remove), Add button, caps |

---

### Task 1: Data model — `AlertWindow` + `UsageAlert`

**Files:**
- Modify: `ClaudeUsageWidget/Models.swift` (append at end, after line 96)

- [ ] **Step 1: Append the model types**

Add to the end of `ClaudeUsageWidget/Models.swift`:

```swift

// MARK: - Usage Alerts

enum AlertWindow: String, Codable, CaseIterable {
    case hour, week

    /// Short label for the segmented toggle.
    var label: String { self == .hour ? "5h" : "Wk" }
    /// Human label used in the notification body.
    var notifLabel: String { self == .hour ? "5-hour" : "Weekly" }
}

struct UsageAlert: Codable, Identifiable, Equatable {
    var id = UUID()
    var window: AlertWindow
    var threshold: Int   // 5...100, multiples of 5
}
```

- [ ] **Step 2: Compile to verify it builds**

Run:
```bash
swiftc ClaudeUsageWidget/*.swift -o bin/ClaudeUsageWidget -framework SwiftUI -framework AppKit -framework Security -framework UserNotifications -target arm64-apple-macos13.0
```
Expected: compiles with no errors. (Existing `AlertService.check` still references the old `threshold:` signature — that's fine, it's untouched this task and still valid.)

- [ ] **Step 3: Commit**

```bash
git add ClaudeUsageWidget/Models.swift
git commit -m "feat: add UsageAlert model and AlertWindow enum"
```

---

### Task 2: Firing logic — per-alert `AlertService.check`

**Files:**
- Modify: `ClaudeUsageWidget/AlertService.swift:7-44`

- [ ] **Step 1: Replace `check` with the per-alert version**

Replace the entire `check(...)` function (lines 7-27) with:

```swift
    /// Check each alert against its window. `alerted` tracks fired alerts keyed
    /// by "window-threshold"; an entry is cleared when its window drops 5% below
    /// the alert's threshold (re-arm).
    static func check(stats: UsageStats, alerts: [UsageAlert], alerted: inout Set<String>) {
        for alert in alerts {
            let stat = alert.window == .hour ? stats.hour : stats.week
            guard stat.available else { continue }

            let key = "\(alert.window.rawValue)-\(alert.threshold)"
            if stat.pct >= Double(alert.threshold) {
                if !alerted.contains(key) {
                    alerted.insert(key)
                    fire(label: alert.window.notifLabel,
                         pct: stat.pct,
                         resetTime: stat.resetTime,
                         identifier: "usage-alert-\(key)")
                }
            } else if stat.pct < Double(alert.threshold) - 5.0 {
                alerted.remove(key)
            }
        }
    }
```

- [ ] **Step 2: Update `fire` to take an identifier**

Replace the `fire(...)` function (lines 29-44) with:

```swift
    private static func fire(label: String, pct: Double, resetTime: Date?, identifier: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Claude Usage"
            content.body = "\(label) at \(Int(pct))%\(resetSuffix(resetTime))"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            center.add(request, withCompletionHandler: nil)
        }
    }
```

Leave `resetSuffix(_:)` (lines 46-58) unchanged.

- [ ] **Step 3: Compile**

Run the compile command. Expected: **FAILS** at `UsageService.swift:149` — the old call site still passes `threshold:`. This is expected; Task 3 fixes the caller. (If you want a clean compile checkpoint, do Task 3 before re-running.)

- [ ] **Step 4: Commit**

```bash
git add ClaudeUsageWidget/AlertService.swift
git commit -m "feat: per-alert firing logic in AlertService"
```

---

### Task 3: Service — `alerts` array, persistence, migration

**Files:**
- Modify: `ClaudeUsageWidget/UsageService.swift:23-29` (property + keys)
- Modify: `ClaudeUsageWidget/UsageService.swift:44-48` (init)
- Modify: `ClaudeUsageWidget/UsageService.swift:149` (call site)

- [ ] **Step 1: Replace the `alertThreshold` property and keys**

Replace lines 23-29:

```swift
    @Published var alertThreshold: Int {
        didSet { UserDefaults.standard.set(alertThreshold, forKey: Self.alertKey) }
    }

    private static let pinnedKey  = "pinnedWindow"
    private static let refreshKey = "refreshIntervalMinutes"
    private static let alertKey   = "alertThreshold"
```

with:

```swift
    @Published var alerts: [UsageAlert] {
        didSet {
            if let data = try? JSONEncoder().encode(alerts) {
                UserDefaults.standard.set(data, forKey: Self.alertsKey)
            }
        }
    }

    private static let pinnedKey      = "pinnedWindow"
    private static let refreshKey     = "refreshIntervalMinutes"
    private static let alertsKey      = "usageAlerts"
    private static let legacyAlertKey = "alertThreshold"
```

- [ ] **Step 2: Replace the init alert-loading + log line**

Replace line 44:

```swift
        self.alertThreshold = UserDefaults.standard.integer(forKey: Self.alertKey)
```

with this migration block:

```swift
        if let data = UserDefaults.standard.data(forKey: Self.alertsKey),
           let decoded = try? JSONDecoder().decode([UsageAlert].self, from: data) {
            self.alerts = decoded
        } else if UserDefaults.standard.integer(forKey: Self.legacyAlertKey) > 0 {
            // Migrate the old single threshold to one Weekly alert, persist it,
            // and drop the legacy key so this runs only once.
            let legacy = UserDefaults.standard.integer(forKey: Self.legacyAlertKey)
            let seeded = [UsageAlert(window: .week, threshold: legacy)]
            self.alerts = seeded
            if let data = try? JSONEncoder().encode(seeded) {
                UserDefaults.standard.set(data, forKey: Self.alertsKey)
            }
            UserDefaults.standard.removeObject(forKey: Self.legacyAlertKey)
        } else {
            self.alerts = []
        }
```

Then replace line 48:

```swift
        log("🔧 UsageService init — refresh=\(refreshMinutes)m alert=\(alertThreshold)%")
```

with:

```swift
        log("🔧 UsageService init — refresh=\(refreshMinutes)m alerts=\(alerts.count)")
```

- [ ] **Step 3: Update the call site**

Replace line 149:

```swift
            AlertService.check(stats: newStats, threshold: alertThreshold, alerted: &alertedWindows)
```

with:

```swift
            AlertService.check(stats: newStats, alerts: alerts, alerted: &alertedWindows)
```

- [ ] **Step 4: Compile**

Run the compile command. Expected: **FAILS** at `MenuBarView.swift:272-277` — the settings UI still references `service.alertThreshold`. Task 4 fixes it. (Models + AlertService + UsageService are now mutually consistent.)

- [ ] **Step 5: Commit**

```bash
git add ClaudeUsageWidget/UsageService.swift
git commit -m "feat: store alerts array with JSON persistence and legacy migration"
```

---

### Task 4: UI — editable alert rows in settings

**Files:**
- Modify: `ClaudeUsageWidget/MenuBarView.swift:270-281` (replace the alert section)
- Modify: `ClaudeUsageWidget/MenuBarView.swift` (add helper funcs inside `SettingsView`, after `pillButton`, before the closing `}` at line 339)

- [ ] **Step 1: Replace the old alert pill section**

Replace lines 270-281 (the `settingsSection("Alert when usage exceeds") { ... }` block) with:

```swift
            settingsSection("Alerts") {
                VStack(spacing: 6) {
                    if service.alerts.isEmpty {
                        Text("No alerts — you won't be notified")
                            .font(.system(size: 9))
                            .foregroundColor(Color(red: 0.353, green: 0.353, blue: 0.376))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach($service.alerts) { $alert in
                        alertRow($alert)
                    }
                    if service.alerts.count < 6 {
                        Button(action: addAlert) {
                            Text("+ Add alert")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(red: 0.557, green: 0.557, blue: 0.576))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(Color(red: 0.227, green: 0.227, blue: 0.250),
                                                style: StrokeStyle(lineWidth: 1, dash: [3]))
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Max alerts reached (3 per window)")
                            .font(.system(size: 9))
                            .foregroundColor(Color(red: 0.388, green: 0.388, blue: 0.400))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
```

- [ ] **Step 2: Add the row + helper views and mutation funcs**

Insert the following inside `SettingsView`, immediately after the `pillButton(...)` function's closing brace (line 338) and before the struct's closing `}` (line 339):

```swift

    @ViewBuilder
    private func alertRow(_ alert: Binding<UsageAlert>) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                windowSeg("5h", window: .hour, alert: alert)
                windowSeg("Wk", window: .week, alert: alert)
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(Color(red: 0.086, green: 0.086, blue: 0.094)))

            Spacer()

            HStack(spacing: 0) {
                stepBtn("–") {
                    alert.wrappedValue.threshold = max(5, alert.wrappedValue.threshold - 5)
                }
                Text("\(alert.wrappedValue.threshold)%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40)
                stepBtn("+") {
                    alert.wrappedValue.threshold = min(100, alert.wrappedValue.threshold + 5)
                }
            }
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.086, green: 0.086, blue: 0.094)))

            Button(action: { removeAlert(alert.wrappedValue) }) {
                Text("✕")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.353, green: 0.353, blue: 0.376))
            }
            .buttonStyle(.plain)
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(Color(red: 0.137, green: 0.137, blue: 0.153)))
    }

    private func windowSeg(_ title: String, window: AlertWindow, alert: Binding<UsageAlert>) -> some View {
        let selected = alert.wrappedValue.window == window
        return Button(action: { switchWindow(alert, to: window) }) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(selected ? .white : Color(red: 0.557, green: 0.557, blue: 0.576))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? Color(red: 0.039, green: 0.518, blue: 1.000) : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private func stepBtn(_ s: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(s)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 0.784, green: 0.784, blue: 0.800))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }

    private func addAlert() {
        let hourCount = service.alerts.filter { $0.window == .hour }.count
        let window: AlertWindow = hourCount < 3 ? .hour : .week
        service.alerts.append(UsageAlert(window: window, threshold: 80))
    }

    private func switchWindow(_ alert: Binding<UsageAlert>, to window: AlertWindow) {
        guard alert.wrappedValue.window != window else { return }
        // Per-window cap: no-op if the target already holds 3 alerts.
        let inTarget = service.alerts.filter {
            $0.window == window && $0.id != alert.wrappedValue.id
        }.count
        guard inTarget < 3 else { return }
        alert.wrappedValue.window = window
    }

    private func removeAlert(_ alert: UsageAlert) {
        service.alerts.removeAll { $0.id == alert.id }
    }
```

- [ ] **Step 3: Compile (should now be clean)**

Run the compile command. Expected: **PASS** — all four files consistent, binary written to `bin/ClaudeUsageWidget`.

- [ ] **Step 4: Commit**

```bash
git add ClaudeUsageWidget/MenuBarView.swift
git commit -m "feat: editable alert rows with per-window cap in settings"
```

---

### Task 5: Bundle, run, manual verification

**Files:** none (build + manual QA)

- [ ] **Step 1: Build the app bundle**

Run:
```bash
./build.sh
```
Expected: `build/Claude Usage Monitor.app` assembled and signed (no errors).

- [ ] **Step 2: Launch**

Run:
```bash
open 'build/Claude Usage Monitor.app'
```

- [ ] **Step 3: Manual checklist** (open the menu-bar dropdown → settings)

Verify each:
- Empty state shows "No alerts — you won't be notified" + dashed **+ Add alert**.
- **+ Add alert** appends a row defaulting to `5h 80%`.
- Stepper `–`/`+` moves the % in 5-point steps; clamps at 5 and 100.
- Window toggle `[5h | Wk]` switches the row's target (blue = selected).
- Add three `5h` rows → a 4th add defaults to `Wk`; toggling any `Wk` row back to `5h` is a no-op (5h already has 3).
- Fill all 6 → Add button replaced by "Max alerts reached (3 per window)".
- `✕` removes a row.
- Quit and relaunch → alerts persist (JSON in UserDefaults).

- [ ] **Step 4: Verify firing (optional, if a window is near a threshold)**

Set an alert threshold just below a live window's current %. On the next refresh (or set Refresh to 1m), expect a macOS banner: `"5-hour at 90% — resets in 1h 20m"`. Two thresholds on the same window each fire independently.

- [ ] **Step 5: Final commit (if build.sh produced tracked artifacts)**

```bash
git status
# Commit only intentional artifact changes; bin/ and build/ may be gitignored.
git add -A && git commit -m "chore: rebuild app bundle with custom alerts" || echo "nothing to commit"
```
