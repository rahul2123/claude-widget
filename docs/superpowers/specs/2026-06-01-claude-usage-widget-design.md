# Claude Usage Widget — Design Spec

**Date:** 2026-06-01
**Status:** Approved
**Author:** rahul.pal

## Summary

A native macOS menu bar app that shows Claude (Anthropic) subscription usage across
three rolling windows: **5-hour**, **weekly**, and **weekly Sonnet**. Modeled on the
existing `glm-usage-widget` (Swift, raw `swiftc` build, `MenuBarExtra`), but targeting
Anthropic's OAuth usage endpoint and auto-reading credentials from the macOS Keychain.

Delivered in two phases:

- **Phase 1 (this spec):** menu bar app.
- **Phase 2 (deferred):** WidgetKit desktop/Notification Center widget reusing the same
  service layer via an App Group.

## Goals

- Show live utilization % for 5-hour, weekly, and weekly-Sonnet windows.
- Color-coded, pinnable menu bar label.
- Zero-config auth: read the logged-in Claude Code OAuth token from the Keychain.
- Rely on Claude Code's daemon to keep the token fresh (no self-refresh).
- Poll every 5 minutes + manual refresh.

## Non-Goals (Phase 1)

- Multi-account support (single logged-in account only).
- Manual token entry / settings screen.
- OAuth token self-refresh (the Claude Code daemon owns refresh — see below).
- WidgetKit widget (Phase 2).
- Automated test suite (manual verification, matching the GLM repo).

## Data Source

Confirmed live during design:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <oauth access token>
anthropic-beta: oauth-2025-04-20
Content-Type: application/json
```

Response (utilization is a 0–100 float):

```json
{
  "five_hour":        { "utilization": 3.0, "resets_at": "2026-06-01T18:59:59+00:00" },
  "seven_day":        { "utilization": 0.0, "resets_at": "2026-06-05T21:59:59+00:00" },
  "seven_day_sonnet": null,
  "seven_day_opus":   null,
  "extra_usage":      { "is_enabled": false, ... }
}
```

Mapping to the three requested metrics:

| Requested        | API field          |
|------------------|--------------------|
| hour             | `five_hour`        |
| week             | `seven_day`        |
| sonnet week      | `seven_day_sonnet` |

Windows may be `null` (e.g. `seven_day_sonnet` is null on the team plan). Null → rendered
as a greyed "—" bar, never as 0%.

## Architecture

Single-target SwiftUI menu bar app, built with raw `swiftc` (cloning the GLM widget layout).

```
ClaudeUsageWidget/
├── App.swift            MenuBarExtra (.window style) + pinnable colored % label
├── Models.swift         UsageResponse (raw) + UsageStats (display model) + PinnedWindow
├── KeychainAuth.swift   read "Claude Code-credentials"; OAuth refresh + write-back
├── UsageService.swift   ObservableObject; fetch /api/oauth/usage every 5 min
└── MenuBarView.swift    3 progress bars + reset countdowns + Refresh/Quit + About
```

### Data flow

```
UsageService.fetch()
  → KeychainAuth.currentToken()      // read-only; daemon keeps it fresh
  → GET /api/oauth/usage             // Bearer + anthropic-beta header
  → parse UsageResponse
  → publish UsageStats
  → SwiftUI redraw
```

### Phasing

`UsageService`, `Models`, and `KeychainAuth` are written as a self-contained module so the
Phase 2 WidgetKit extension reuses them unchanged via App Group
`group.com.claude.usage-widget` (menu bar app writes cached `UsageStats`, widget reads on
its timeline).

## Data Model

```swift
// Raw API shape
struct UsageResponse: Codable {
    let five_hour: Window?
    let seven_day: Window?
    let seven_day_sonnet: Window?
    let seven_day_opus: Window?
    struct Window: Codable { let utilization: Double; let resets_at: String } // ISO8601
}

// Display model
struct WindowStat { let pct: Double; let resetTime: Date?; let available: Bool }
struct UsageStats {
    let hour: WindowStat        // five_hour
    let week: WindowStat        // seven_day
    let sonnetWeek: WindowStat  // seven_day_sonnet
    let lastUpdated: Date
}

enum PinnedWindow { case highest, hour, week, sonnet }  // persisted in UserDefaults
```

- Null API window → `WindowStat(available: false)`.
- `resets_at` parsed as ISO8601 → countdown ("resets in 2h 14m" / "resets Jun 5").
- Menu bar label shows the pinned window's %; `.highest` → max of available windows.

## Keychain Auth (read-only)

**Strategy: read-only. The widget never refreshes the token itself.**

Rationale (confirmed empirically during design): Claude Code runs a persistent background
daemon (`claude daemon run`) that proactively refreshes the OAuth token roughly every 8
hours and writes it back to the Keychain. `daemon.log` shows a steady cadence:

```
auth: proactive refresh succeeded
auth: scheduling proactive refresh in 28560s   # ≈ 7.93h
```

Because the daemon owns refresh, the keychain token is fresh nearly all the time. The widget
duplicating that refresh would add a fragile dependency (OAuth endpoint host + `client_id`,
both subject to change) and risk a keychain write-back conflict with the daemon. So the
widget only reads.

**Read:** `KeychainAuth.currentToken()` reads the generic-password item
`service: "Claude Code-credentials"` via the Security framework (`SecItemCopyMatching`).
Value JSON: `{ claudeAiOauth: { accessToken, refreshToken, expiresAt, ... } }`. The widget
uses `accessToken` (and reads `expiresAt` only to display token expiry / detect the stale
window). First run triggers one OS keychain-access prompt — user clicks **Always Allow**.

**Stale window:** in rare cases (daemon not running and token already expired — observed as
`daemon-auth-status.json` = `auth_required`), the token may be expired. The widget detects
this via `expiresAt` in the past and/or an HTTP 401, and surfaces a clear
"Token stale — open Claude Code to refresh" state. It self-heals automatically on the next
fetch once the daemon (or any Claude Code launch) refreshes the token. No action by the
widget beyond re-reading the keychain.

**Secrets handling:** tokens never logged (redacted to first 8 chars, matching GLM widget).
No tokens written to disk; the widget never writes to the Keychain.

**Future upgrade (not in scope):** if the stale window proves disruptive in practice, a 401
fallback self-refresh (OAuth `refresh_token` grant + write-back) can be added later. Tracked
as a follow-up, deliberately excluded from v1 to avoid the fragile endpoint/`client_id`
dependency.

## UI Layout

Menu bar label: pinned window's % + color dot. Green/yellow/orange/red at 50/70/90%.

Dropdown (`MenuBarExtra` `.window` style, ~280pt wide):

```
┌────────────────────────────────┐
│ Claude Usage          ⟳  ⚙      │
├────────────────────────────────┤
│ 5-hour          3%   ▓░░░░░░░░░ │
│   resets in 2h 14m             │
│ Week            0%   ░░░░░░░░░░ │
│   resets Jun 5                 │
│ Sonnet (week)   —    ┈┈┈┈┈┈┈┈┈┈ │  ← greyed, null
│   not available                │
├────────────────────────────────┤
│ ◉ highest  ○ 5h  ○ week  ○ son │  ← pin radios
├────────────────────────────────┤
│ updated 19:42      Refresh  Quit│
└────────────────────────────────┘
```

- Each available window: label, %, color-coded progress bar, reset countdown.
- Null window: greyed dashed bar, "not available".
- Pin radios set `PinnedWindow` (persisted).
- Footer: last-updated timestamp, Refresh (forces immediate fetch), Quit.
- Gear opens an About/status popover: account email + token expiry. No settings screen
  (auto-keychain = zero config).

## Error Handling

All states render in the dropdown; the app never crashes.

| Condition                          | Display                                        |
|------------------------------------|------------------------------------------------|
| No keychain item                   | "Not logged in — run Claude Code first"        |
| Keychain access denied             | "Keychain access denied — click Allow"         |
| Expired token / HTTP 401           | "Token stale — open Claude Code to refresh"    |
| Network error                      | "Offline — retrying" + dimmed last-good values |

## Refresh Cadence

- Fetch on launch.
- Timer every 5 minutes (matching GLM widget).
- Manual Refresh button forces an immediate fetch.

## Testing

No test target (matches GLM repo). Manual verification:

1. `curl` probe confirms endpoint + parses 3 windows (verified live during design ✓).
2. Build + `open`, click menu bar, confirm 3 bars render with live values.
3. Stale-token render: simulate a 401 / past `expiresAt` → confirm
   "Token stale — open Claude Code" state shows and clears on next good fetch.
4. Null-window render: confirm Sonnet shows greyed.

## Build

```bash
# compile
swiftc -o bin/ClaudeUsageWidget ClaudeUsageWidget/*.swift \
  -framework SwiftUI -framework AppKit -framework Foundation -framework Security

# package into app bundle
./build.sh   # → build/Claude Usage Monitor.app

# run
open 'build/Claude Usage Monitor.app'
```

First launch: right-click → Open to bypass Gatekeeper (unsigned binary), then Always Allow
the keychain prompt.

## Phase 2 — WidgetKit (Deferred, out of scope)

Separate Xcode project; App Group `group.com.claude.usage-widget` shares the cached
`UsageStats`. Menu bar app writes; the widget extension reads on its timeline. Tracked as a
follow-up after Phase 1 ships.
