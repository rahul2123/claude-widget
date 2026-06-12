# Claude Usage Monitor

A macOS menu bar widget that shows your [Claude Code](https://claude.ai/code) token usage in real time. Reads the OAuth token Claude Code stores in your keychain — no separate login, no API key.

![Menu bar showing Claude logo and usage percentage](ClaudeUsageWidget/Resources/claude-logo.png)

---

## What it shows

- **5-hour window** usage %
- **Weekly** usage %
- **Sonnet (weekly)** usage %
- Color coding: green < 50%, amber < 70%, orange < 90%, red ≥ 90%
- Reset countdowns per window
- Pinnable metric in the menu bar label
- Optional always-on-top floating desktop widget
- Auto-refreshes every 5 minutes

## Requirements

- macOS 13.0+ (Apple Silicon / arm64)
- [Claude Code](https://claude.ai/code) installed and logged in (provides the keychain token)
- Xcode Command Line Tools (`xcode-select --install`)
- OpenSSL 3 (`brew install openssl@3`)

---

## Quick start

### 1. Clone

```bash
git clone https://github.com/rahul2123/claude-widget.git
cd claude-widget
```

### 2. Create a signing certificate (once per machine)

This is the key step. The app reads a keychain item owned by Claude Code. macOS asks "Allow / Always Allow / Deny" the first time any app touches it. If the app is signed with **ad-hoc** (`codesign --sign -`), the "Always Allow" decision is tied to the binary's content hash (cdhash) and dies every time you rebuild. Signing with a **stable self-signed certificate** ties the decision to the cert's fingerprint instead — authorize once and it persists forever.

```bash
./create-signing-cert.sh
```

This is idempotent — safe to run multiple times, does nothing if the cert already exists. Never delete or regenerate the cert: a new cert has a different fingerprint and forces re-authorization.

### 3. Build

```bash
# Compile
swiftc ClaudeUsageWidget/*.swift \
  -o bin/ClaudeUsageWidget \
  -framework SwiftUI -framework AppKit -framework Security -framework UserNotifications \
  -target arm64-apple-macos13.0

# Bundle (signs automatically with the cert from step 2)
./build.sh
```

### 4. Install and launch

```bash
cp -R 'build/Claude Usage Monitor.app' /Applications/
open '/Applications/Claude Usage Monitor.app'
```

**First launch only:** macOS will show a keychain prompt — click **Always Allow**. That's it. Every future rebuild and relaunch is silent.

> **Gatekeeper note:** On first launch macOS may say the app is from an unidentified developer. Right-click the app → **Open** → **Open** to bypass.

---

## Rebuilding after source changes

```bash
swiftc ClaudeUsageWidget/*.swift \
  -o bin/ClaudeUsageWidget \
  -framework SwiftUI -framework AppKit -framework Security \
  -target arm64-apple-macos13.0

./build.sh

# Reinstall
pkill -f "Claude Usage Monitor.app" 2>/dev/null || true
rm -rf '/Applications/Claude Usage Monitor.app'
cp -R 'build/Claude Usage Monitor.app' /Applications/
open '/Applications/Claude Usage Monitor.app'
```

No keychain prompt — the cert fingerprint hasn't changed.

---

## How it works

```
Keychain ("Claude Code-credentials")
  → KeychainAuth.loadCredentials()
    → UsageService.fetchUsage()
      → GET https://api.anthropic.com/api/oauth/usage
          (header: anthropic-beta: oauth-2025-04-20)
        → UsageResponse → UsageStats
          → MenuBarView + DesktopWidgetView
```

Claude Code's background daemon keeps the token fresh. This app only reads it — never writes, never refreshes.

---

## Project layout

| File | Role |
|---|---|
| `App.swift` | `@main`, `MenuBarExtra`, `ClaudeLogo`, `UsageColor` |
| `UsageService.swift` | `ObservableObject`; fetches API every 5 min, publishes stats |
| `KeychainAuth.swift` | Read-only keychain access for Claude Code's OAuth token |
| `Models.swift` | `UsageResponse` (API shape) → `WindowStat` / `UsageStats` (display) |
| `MenuBarView.swift` | Dropdown panel: window rows, pin selector, footer |
| `DesktopWidget.swift` | Floating `NSPanel` always-on-top widget (draggable, persisted position) |
| `build.sh` | Assemble app bundle, sign with local cert |
| `create-signing-cert.sh` | One-time self-signed code-signing cert setup |

No Xcode, no Swift Package Manager, no test suite — `swiftc` direct compile only.

---

## Signing details (why / how)

macOS stores a keychain "Always Allow" grant as the app's *designated requirement* (DR). The DR is matched on every access:

| Signing method | DR | Survives rebuild? |
|---|---|---|
| Ad-hoc (`--sign -`) | `cdhash:<binary hash>` | **No** — any source change = new hash = re-prompt |
| Self-signed cert | `identifier … and certificate leaf = H"<cert fingerprint>"` | **Yes** — cert fingerprint is constant |

`create-signing-cert.sh` creates a 10-year self-signed certificate in your login keychain with `codeSigning` extended key usage. `build.sh` signs the bundle with it. The cert's SHA-1 fingerprint never changes, so the DR always matches.

Debug log at `/tmp/claude-usage-widget.log` (tokens are never logged).

---

## Troubleshooting

**Keychain prompt appears again after rebuild**
The cert is missing or was regenerated. Run `./create-signing-cert.sh` (idempotent), rebuild, and click Always Allow once more.

**"Not logged in — run Claude Code first"**
Claude Code is not installed or you haven't logged in. Open Claude Code and sign in.

**"Token stale — open Claude Code to refresh"**
Claude Code's daemon hasn't refreshed the token yet. Open Claude Code briefly; the daemon refreshes automatically.

**App doesn't appear in menu bar**
Check `/tmp/claude-usage-widget.log` for errors.

**Gatekeeper blocks launch**
Right-click the app → Open → Open. Only needed once per install.
