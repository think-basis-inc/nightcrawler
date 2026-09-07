# NightCrawler

A tiny, native macOS HUD that sits on the edge of your screen and shows how much of each AI-coding subscription you’ve burned. It reads credentials each tool already stores locally, so there’s no sign-in, no Electron, no telemetry.

Built for people who run multiple agents (Claude Code, Codex, Cursor, GitHub Copilot, Grok, OpenCode, Antigravity, ZCode / GLM) and want one honest glance at their remaining headroom.

## Look

- A small, rounded tab floats on the right, left, top, or bottom edge of the screen.
- Each enabled provider shows as an icon with a colored ring around it: green → amber → red.
- Hover an icon for the percentage, used / limit, and reset time.
- Click an icon to pop out the full data panel.

## Why not a fork of codenotch?

[codenotch](https://github.com/vinzdg/codenotch) proved the idea and is excellent, but forking it would keep an upstream link and PR expectations. NightCrawler is a clean-room rewrite under `think-basis-inc`, taking inspiration from codenotch plus [Pulse](https://github.com/Byte-de/pulse), [Tokcat](https://github.com/handlecusion/tokcat), [Throttle](https://github.com/momenbuilds/throttle). It is ours to extend.

## Architecture

```
Sources/NightCrawler/
  NightCrawlerApp.swift      @main + NSApplication delegate
  AppDelegate.swift          menu-bar status item + HUD host
  Model/
    UsageReading.swift       one normalized limit reading
    UsageStore.swift         polls providers, publishes to UI
  Providers/
    UsageProvider.swift      protocol
    GitHubCopilotUsageProvider.swift  example real provider
  UI/
    HUDView.swift            floating edge tab with icon rings
    RingView.swift           status-colored ring
    SettingsView.swift       provider toggles
    FloatingHUDController.swift  NSPanel positioning
```

## Build

```bash
swift build
swift test
```

Install to `/Applications`:

```bash
./scripts/install.sh
```

## Provider setup

NightCrawler reads credentials the tools already store locally. Install and sign in to each tool, then NightCrawler will pick them up automatically.

| Provider | What it reads |
|---|---|
| Claude Code | `Claude Code-credentials` item in the macOS Keychain |
| Codex CLI | `~/.codex/auth.json` |
| Cursor | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` |
| GitHub Copilot | `nightcrawler.github.copilot` Keychain item (PAT with `Plan` read-only) |
| Grok | `~/.grok/auth.json` |
| OpenCode | `~/.local/share/opencode/auth.json` |
| Antigravity | `gemini` / `antigravity` Keychain item |
| ZCode / GLM | `~/.claude/settings.json`, `~/.zcode/v2/config.json`, or `~/.local/share/opencode/auth.json` |

Add the Copilot PAT:

```bash
security add-generic-password -s "nightcrawler.github.copilot" -a "token" -w "ghp_..."
```

## License

MIT. Provider names and marks belong to their respective owners.
