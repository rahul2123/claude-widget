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

`build.sh` assembles `build/Claude Usage Monitor.app` — copies binary, Info.plist, logo PNG, generates `.icns` via `sips`/`iconutil`, and code-signs with the stable self-signed identity `Claude Widget Code Signing` (ad-hoc fallback if absent).

To run after building:
```bash
open 'build/Claude Usage Monitor.app'
```

### Code signing & keychain persistence

The app reads Claude Code's OAuth token from the keychain. macOS stores the "Always Allow" decision as the calling app's *designated requirement*. Ad-hoc signing yields a cdhash-based identity that changes every rebuild, so the decision dies and macOS re-prompts. Signing with a certificate gives a cert-leaf-based DR (`identifier "com.claudeusagewidget.app" and certificate leaf = H"…"`) that survives rebuilds.

First-time setup on a machine (run once):
```bash
./create-signing-cert.sh   # creates persistent self-signed code-signing cert in login keychain
./build.sh                 # signs with it
```
Then launch and click **Always Allow** at the keychain prompt — once. Future rebuilds keep the same DR, so no further prompts. The cert is local/self-signed (no Apple account); `create-signing-cert.sh` is idempotent — never regenerate, or the DR changes and you re-authorize.

No Xcode, no SPM, no test suite — `swiftc` direct compile only.

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
