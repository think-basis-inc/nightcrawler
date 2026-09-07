# NightCrawler roadmap

A tiny macOS HUD that floats on the screen edge and reports AI-coding subscription usage. It reads credentials each tool already stores locally and shows remaining headroom as icon rings.

## Phase 0 — skeleton (done)

- [x] Create `think-basis-inc/nightcrawler` repo
- [x] Swift Package Manager project with executable target
- [x] Floating edge HUD shell (rounded tab, always-on-top, positionable)
- [x] Provider icons with colored usage rings
- [x] Hover tooltip with usage percentage and limits
- [x] `UsageProvider` protocol + `UsageStore`
- [x] Example `GitHubCopilotUsageProvider` (reads PAT from Keychain)
- [x] Build + install scripts

## Phase 1 — click-to-pop-out detail panel

- [ ] Click an icon to open a compact detail popover/panel
- [ ] Show per-provider windows: session / daily / weekly / monthly limits
- [ ] Reset countdown and limit breakdown

## Phase 2 — core providers (read local credentials, call official APIs)

- [ ] Claude Code provider (OAuth token from Keychain → Anthropic usage endpoint)
- [ ] Codex CLI provider (local Codex session → OpenAI usage endpoint)
- [ ] Cursor provider (local SQLite/session → Cursor usage endpoint)
- [ ] Grok provider (`~/.grok/auth.json` → Grok credits endpoint)
- [ ] OpenCode provider (`opencode-go` key → OpenCode plan endpoint)
- [ ] Antigravity / GLM / ZCode providers
- [ ] Provider availability detection: hide providers with no local credentials

## Phase 3 — placement and behavior

- [ ] Choose edge: right, left, top, bottom (currently hard-coded right)
- [ ] Remember HUD position across launches
- [ ] Compact vs expanded icon sizes
- [ ] Refresh cadence (idle vs active)
- [ ] Launch at login

## Phase 4 — reliability and efficiency

- [ ] 429/penalty-aware back-off per provider
- [ ] Persist last readings across launches
- [ ] Low CPU when idle; poll faster only when a live session is detected
- [ ] Unified logging via `os.log`
- [ ] Demo mode (`NIGHTCRAWLER_DEMO=1`) for screenshots/tests

## Phase 5 — distribution

- [ ] Signed/notarized release build via GitHub Actions
- [ ] Sparkle auto-updater
- [ ] Homebrew cask
