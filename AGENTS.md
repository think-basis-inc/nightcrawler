# NightCrawler — coding and verification

Native Swift/SwiftUI/AppKit macOS HUD with a loopback-only capacity endpoint.
Read `README.md` and the relevant source/tests; `Package.swift` owns the minimum
toolchain/platform requirements. Do not treat those minimums as proof that the
installed toolchain is current. Verify current official support when changing it.

Use shared `ship-pipeline`, `model-currency` and `regression-test-guardian`.
Build rapidly in coherent increments, running affected tests continuously.
Full independent reviews belong at a settled checkpoint, not after each tweak.

## Test the boundary that changed

| Change | Evidence needed |
|---|---|
| Parsing, normalization, geometry | Focused Swift tests with invalid, boundary and partial inputs |
| Provider refresh/store state | Sequence tests through the real store: complete → partial/error/stale → recovery; preserve per-window age |
| Endpoint | Real loopback HTTP/serialization checks for schema, availability, freshness and secret exclusion |
| HUD click/layout/settings | Native hit-testing/event behavior plus actual clicks in the running app; AX activation alone does not prove mouse dispatch |
| Process/credential adapters | Bounded subprocess/timeout fixtures and isolated contract checks; never print credentials or prompt a model just to collect quota |

Run `swift build` and `swift test` for product delivery. Swift Testing may report
after an empty XCTest summary: verify actual test collection and failures.
A named bug needs a test that fails on the broken behavior before the fix.
Source-string assertions, demo-only readings and direct state forcing do not
prove the user interaction or provider refresh behavior named by the test.

Use a separate scratch build path if another session builds concurrently.
Do not install/relaunch over the user's running app as a verification shortcut.
`scripts/install.sh` replaces the installed app; installation is a separate,
explicitly scoped action. Label source, tested build and installed build clearly.

## Capacity and access

The app's documented adapters read existing CLI credentials; this does not
authorize agents to dump auth stores or copy secrets. Keep quota reads bounded
and read-only. Use existing shared access procedures before rediscovering login.

`http://127.0.0.1:17890/v1/capacity` is a local observation endpoint, not a
model catalog, billing authorization, shared-pool reservation or universal
router. Demo/stale/unknown/partial data is not included capacity. Do not infer
missing windows are unlimited, or assume another host's loopback is this Mac.
Preserve loopback-only binding and secret/account-identifier exclusion.

No paid generation, extra usage, account changes or automatic fallback is
authorized by a monitoring task. Model-specific limits and applicable provider
windows both matter; required reviews remain outstanding if capacity runs out.
