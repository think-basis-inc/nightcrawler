# NightCrawler

A tiny, native macOS app that pins your AI-coding-agent usage and limits to the screen edge or menu bar. Choose which providers to show, where the pill lives, and how often it refreshes. No Electron, no bundled browser, no telemetry.

Built for people who run multiple agents (Claude Code, Codex, Cursor, GitHub Copilot, Grok, Gemini, OpenCode, Antigravity, ZCode / GLM) and want one honest glance at their remaining headroom.

## Why not a fork of codenotch?

[codenotch](https://github.com/vinzdg/codenotch) proved the idea and is excellent, but forking it would keep an upstream link and PR expectations. NightCrawler is a clean-room rewrite under `think-basis-inc`, taking inspiration from codenotch plus [Pulse](https://github.com/Byte-de/pulse), [Tokcat](https://github.com/handlecusion/tokcat), [Throttle](https://github.com/momenbuilds/throttle), and the per-agent visibility lessons from Dino. It is ours to extend.

## What it shows

- **Per-provider rings/bars** for session, daily, weekly, or monthly windows — whichever limit is closest to the cap.
- **Pick your providers** in Settings; only installed/active ones take up space.
- **Copilot premium requests** via GitHub's billing API, using a PAT you store in the Keychain.
- **Threshold notifications** before you hit the wall.
- **Lightweight**: Swift + SwiftUI/AppKit, menu-bar-first, optional floating pill on the right/left/top/bottom edge.

## Architecture

```
Sources/NightCrawler/
  NightCrawlerApp.swift      @main + NSApplication delegate
  AppDelegate.swift          menu-bar status item + popover host
  Model/
    UsageReading.swift       one normalized limit reading
    UsageStore.swift         polls providers, publishes to UI
  Providers/
    UsageProvider.swift      protocol
    GitHubCopilotUsageProvider.swift  example real provider
  UI/
    PopoverView.swift        menu-bar popover
    SettingsView.swift       provider toggles
    RingView.swift           status-colored ring
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

## Copilot setup

NightCrawler reads a GitHub Personal Access Token from the macOS Keychain:

```bash
security add-generic-password -s "nightcrawler.github.copilot" -a "token" -w "ghp_..."
```

The token only needs **Account permissions → Plan → Read-only**.

## License

MIT. Provider names and marks belong to their respective owners.
