# NightCrawler roadmap

A tiny macOS HUD that floats on the screen edge and reports AI-coding subscription usage. It reads credentials each tool already stores locally and shows remaining headroom as icon rings.

## Phase 0 — skeleton (done)

- [x] Create `think-basis-inc/nightcrawler` repo
- [x] Swift Package Manager project with executable target
- [x] Floating edge HUD shell (rounded tab, always-on-top, positionable)
- [x] Provider icons with colored usage rings
- [x] Hover tooltip with usage percentage and limits
- [x] `UsageProvider` protocol + `UsageStore`
- [x] Build + install scripts

## Phase 1 — providers (done)

- [x] Claude Code provider (Keychain → Anthropic usage endpoint)
- [x] Codex CLI provider (`~/.codex/auth.json` → ChatGPT usage endpoint)
- [x] Cursor provider (SQLite global state → cursor.com usage summary)
- [x] GitHub Copilot provider (Keychain PAT → GitHub billing API)
- [x] Grok provider (`~/.grok/auth.json` → Grok CLI billing endpoint)
- [x] OpenCode provider (`~/.local/share/opencode/auth.json`)
- [x] Antigravity provider (Keychain → Google Cloud Code backend)
- [x] ZCode / GLM provider (multi-source credential discovery)
- [x] Provider availability detection: only show providers whose local credentials exist

## Phase 2 — click-to-pop-out detail panel (done)

- [x] Click an icon to open a compact detail popover/panel
- [x] Show per-provider windows: session / daily / weekly / monthly limits
- [x] Reset countdown and limit breakdown

## Phase 3 — placement and behavior (partial)

- [x] Choose edge: right, left, top, bottom
- [x] Remember HUD position across launches
- [ ] Compact vs expanded icon sizes
- [ ] Refresh cadence (idle vs active)
- [x] Launch at login

## Phase 4 — reliability and efficiency

- [x] 429/penalty-aware back-off per provider (handled in provider responses)
- [ ] Persist last readings across launches
- [ ] Low CPU when idle; poll faster only when a live session is detected
- [ ] Unified logging via `os.log`
- [x] Demo mode (`NIGHTCRAWLER_DEMO=1` or menu bar toggle) for screenshots/tests

## Phase 5 — distribution

- [ ] Signed/notarized release build via GitHub Actions
- [ ] Sparkle auto-updater
- [ ] Homebrew cask
