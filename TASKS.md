# NightCrawler roadmap

A tiny macOS subscription/usage reporter for AI coding agents. It reads credentials each tool already stores locally and shows remaining headroom in the menu bar or a floating edge panel.

## Phase 0 — skeleton (done)

- [x] Create `think-basis-inc/nightcrawler` repo
- [x] Swift Package Manager project with executable target
- [x] Menu-bar app shell, popover, settings, ring view
- [x] `UsageProvider` protocol + `UsageStore`
- [x] Example `GitHubCopilotUsageProvider` (reads PAT from Keychain)
- [x] Build + install scripts

## Phase 1 — core providers (read local credentials, call official APIs)

- [ ] Claude Code provider (OAuth token from Keychain → Anthropic usage endpoint)
- [ ] Codex CLI provider (local Codex session → OpenAI usage endpoint)
- [ ] Cursor provider (local SQLite/session → Cursor usage endpoint)
- [ ] Grok provider (`~/.grok/auth.json` → Grok credits endpoint)
- [ ] OpenCode provider (`opencode-go` key → OpenCode plan endpoint)
- [ ] Antigravity / GLM / ZCode providers
- [ ] Provider availability detection: hide providers with no local credentials

## Phase 2 — display options

- [ ] Per-provider visibility toggles (Settings UI already started)
- [ ] Choose surface: menu bar only, floating edge pill, or both
- [ ] Choose pill edge: right, left, top, bottom
- [ ] Compact vs expanded view
- [ ] Refresh cadence (idle vs active)
- [ ] Launch at login

## Phase 3 — richer reporting

- [ ] Floating edge pill window with position persistence
- [ ] Hover tooltip with reset time and limit window details
- [ ] Multiple limit windows per provider (session / daily / weekly / monthly)
- [ ] Threshold notifications at 70% / 90%
- [ ] Menu-bar title mode: icon-only, total %, hottest provider

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
