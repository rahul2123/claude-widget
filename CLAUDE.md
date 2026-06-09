# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git Rules

- **Never add co-author lines** to commits. No `Co-Authored-By` trailers ever.
- Use `rahul2123` GitHub account for this repo.

## Build

Compile the binary, then assemble the app bundle:

```bash
# Compile (from repo root)
swiftc ClaudeUsageWidget/*.swift \
  -o bin/ClaudeUsageWidget \
  -framework SwiftUI -framework AppKit -framework Security \
  -target arm64-apple-macos13.0

# Bundle
./build.sh
```

`build.sh` assembles `build/Claude Usage Monitor.app` — copies binary, Info.plist, logo PNG, and generates `.icns` via `sips`/`iconutil`.

To run after building:
```bash
open 'build/Claude Usage Monitor.app'
```

First launch on a new machine: right-click → Open (unsigned binary). macOS will also prompt to allow Keychain access — click Allow.

No Xcode, no SPM, no test suite — `swiftc` direct compile only.

## Architecture

Six Swift files, no dependencies beyond Apple frameworks:

| File | Role |
|---|---|
| `App.swift` | `@main`, `MenuBarExtra` setup, `ClaudeLogo`/`UsageColor` |
| `UsageService.swift` | ObservableObject; fetches API every 5 min, publishes stats |
| `KeychainAuth.swift` | Read-only keychain access for Claude Code's OAuth token |
| `Models.swift` | `UsageResponse` (API shape) → `WindowStat`/`UsageStats` (display) |
| `MenuBarView.swift` | Dropdown panel: three window rows, pin selector, footer |
| `DesktopWidget.swift` | Floating `NSPanel` widget (always-on-top, draggable, UserDefaults position) |

### Data flow

```
Keychain ("Claude Code-credentials")
  → KeychainAuth.loadCredentials()
    → UsageService.fetchUsage()
      → GET https://api.anthropic.com/api/oauth/usage
        (header: anthropic-beta: oauth-2025-04-20)
        → UsageResponse → UsageStats
          → MenuBarView + DesktopWidgetView
```

Claude Code's daemon refreshes the keychain token. This app only reads it.

### Key behaviors

- **Pinned window** (`PinnedWindow` enum): user picks which of the four windows (highest/hour/week/sonnet) appears in the menu bar label. Persisted in UserDefaults.
- **Color coding** (`UsageColor`): green < 50%, amber < 70%, orange < 90%, red ≥ 90%.
- **Desktop widget** (`DesktopWidgetController`): borderless `NSPanel`, level `.floating`, no Xcode WidgetKit involved. Position + visibility in UserDefaults.
- **Logging**: debug output → `/tmp/claude-usage-widget.log` (no tokens logged).
- **LSUIElement = true**: no Dock icon, menu bar only.
