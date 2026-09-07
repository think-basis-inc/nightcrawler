# NightCrawler

A tiny, native macOS HUD that sits on the edge of your screen and shows how much of each AI-coding subscription you’ve burned. It reads credentials each tool already stores locally, so there’s no sign-in, no Electron, no telemetry.

Built for people who run multiple agents (Claude Code, Codex, Cursor, GitHub Copilot, Grok, OpenCode, Antigravity, ZCode / GLM) and want one honest glance at their remaining headroom.

## Look

- A black rail welds into the chosen screen edge (right, left, top, or bottom) with inverse rounded flares.
- Each enabled provider shows the same compact percentage convention—always percent used—with a colored ring: green under 50%, yellow to 70%, orange to 100%, red when exhausted.
- Claude shows two concentric arcs when both All models and Fable weekly windows exist.
- Click an icon or the tucked settings handle to open an attached slideout joined to the rail by a pinched, curved liquid tendril rather than a popover pointer.

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
    GitHubCopilotUsageProvider.swift  Copilot CLI metadata RPC
  UI/
    HUDRootView.swift        welded rail plus attached slideout
    HUDView.swift            provider rings
    SettingsView.swift       custom provider picker
    FloatingHUDController.swift  single NSPanel on the bezel
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
| GitHub Copilot | Copilot CLI (`copilot --headless --stdio`); metadata-only `account.getQuota` |
| Grok | `~/.grok/auth.json` |
| OpenCode | `~/.local/share/opencode/auth.json` |
| Antigravity | `gemini` / `antigravity` Keychain item |
| ZCode / GLM | `~/.claude/settings.json`, `~/.zcode/v2/config.json`, or `~/.local/share/opencode/auth.json` |

## Demo mode

To see the HUD without connecting any credentials, open the menu bar item and choose **Demo mode**, or launch from the terminal:

```bash
NIGHTCRAWLER_DEMO=1 open /Applications/NightCrawler.app
```

Demo mode is intentionally temporary and returns to live provider data on the next launch.

## Local agent capacity endpoint

While NightCrawler is running, local agents can read its cached routing snapshot without triggering a provider refresh:

```bash
curl http://127.0.0.1:17890/v1/capacity
```

`GET /health` is also available. The listener binds only to `127.0.0.1`, accepts no mutations, and never returns credentials or account identifiers. Each resource reports its persisted `enabled` state, `available` as `available`, `unavailable`, or `unknown`, and capacity windows with freshness and reset times. Tools without an authoritative quota source report unknown capacity. Devin and Cubic appear in the attached Agent routing settings; Cubic starts disabled and unavailable.

## What works now

- Edge-welded HUD with provider icons and colored usage rings
- Click an icon for the per-provider window breakdown in an attached slideout
- Menu bar controls: move the HUD edge, refresh, demo mode, launch at login, settings, quit
- Screen-edge selection plus per-provider visibility and ordering in the attached settings slideout
- Provider order, visibility, routing-tool state, and edge preference persist across restarts
- Loopback-only cached capacity endpoint for local agent routing decisions
- Reads local credentials from each AI tool; no sign-in or token storage inside the app

## License

MIT. Provider names and marks belong to their respective owners.
