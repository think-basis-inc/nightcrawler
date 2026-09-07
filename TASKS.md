# NightCrawler roadmap

## Phase 0 — skeleton (done)

- [x] Create `think-basis-inc/nightcrawler` repo
- [x] Swift Package Manager project with executable target
- [x] Menu-bar app shell, popover, settings, ring view
- [x] `UsageProvider` protocol + `UsageStore`
- [x] Example `GitHubCopilotUsageProvider`
- [x] Build + install scripts

## Phase 1 — port core providers from codenotch

- [ ] Claude Code provider (read OAuth token from Keychain, call Anthropic usage endpoint)
- [ ] Codex CLI provider (read Codex session, call OpenAI usage endpoint)
- [ ] Cursor provider (read local SQLite/session)
- [ ] Grok provider (read `~/.grok/auth.json`)
- [ ] OpenCode provider (read `opencode-go` key)
- [ ] Antigravity / GLM / ZCode providers
- [ ] Provider availability detection: only show providers whose local credentials exist

## Phase 2 — Dino-style configurability

- [ ] Per-provider visibility toggles (Settings UI already started)
- [ ] Choose surface: menu bar only, floating pill, or both
- [ ] Choose pill edge: right, left, top, bottom
- [ ] Compact vs expanded pill
- [ ] Refresh cadence (idle vs active)
- [ ] Launch at login

## Phase 3 — richer UI

- [ ] Floating edge pill window (NSPanel, position remembered)
- [ ] Hover tooltip with reset time and limit window details
- [ ] Per-provider detail panel (multiple windows: session, weekly, monthly)
- [ ] Threshold notifications at 70% / 90%
- [ ] Menu-bar title mode: icon-only, total %, hottest provider

## Phase 4 — honesty and efficiency

- [ ] 429/penalty-aware back-off per provider
- [ ] Persist readings across launches so UI never flashes empty
- [ ] Low CPU when idle; poll faster only when a live session is detected
- [ ] Unified logging via `os.log`
- [ ] Demo mode (`NIGHTCRAWLER_DEMO=1`) for screenshots/tests

## Phase 5 — distribution

- [ ] Signed/notarized release build via GitHub Actions
- [ ] Sparkle auto-updater
- [ ] Homebrew cask
