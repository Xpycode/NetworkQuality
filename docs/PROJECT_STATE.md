# Project State

> **Size limit: <100 lines.** This is a digest, not an archive.

## Identity
- **Project:** NetworkQuality
- **One-liner:** Native macOS app for comprehensive network performance testing and diagnostics
- **Started:** 2025-12-01

## Current Position
- **Phase:** polish
- **Focus:** v1.1.0 (build 1100) prep. Sparkle auto-updates wired and build-verified (menu item, appcast, EdDSA key in 99-AUTH). CHANGELOG has the v1.1.0 entry. Release is fully runnable from the M1 Max (Developer ID cert, notary profile `notary-FDMSRXXN73`, Sparkle key all present). Remaining before release: README feature update, rebuild DMG, notarize, sign appcast entry, fresh screenshots, dark-mode color audit (320 refs).
- **Status:** in progress
- **Last updated:** 2026-07-12

## Progress
```
[##################--] 90% - all v1.1.0 features merged, version bumped, CHANGELOG written; rebuild, notarization, screenshots & dark-mode audit pending
```

| Phase | Status | Notes |
|-------|--------|-------|
| Discovery | done | — |
| Planning | done | — |
| Implementation | done | All features shipped |
| Polish | **active** | Shell migration to Penumbra standard — Phase 4–6 pending |
| Shipping | paused | v1.1.0 needs rebuild + notarization; v1.0.2 is current public release; v1.0.3 retired unshipped |

## Tech Stack
- Swift 5.0, SwiftUI
- macOS 14.0+ native
- Apple `networkQuality` CLI integration
- Cloudflare/M-Lab APIs for multi-server testing

## Active Decisions
- 2026-07-12: Next release is **v1.1.0** (build 1100) — minor bump for the two unreleased feature sets; v1.0.3 retired unshipped, its stale DMG in `APP/` must not be distributed (see [decisions.md](decisions.md)).
- 2026-05-29: Connection Info diagnostics — capture local IPv4+IPv6 (skip loopback/link-local/`::`), independent public v4/v6 + dual-stack badge, gateway/subnet/MTU/DNS (native getifaddrs + SCDynamicStore, no subprocess), VPN/proxy detection. Gateway/DNS/MTU/VPN persisted in `NetworkMetadata`; public IP + badge are live-only.
- 2026-05-29: Bufferbloat letter grade (A+…F) keyed on **absolute added latency (ms)** (Waveform/DSLReports scale), not the loaded/idle multiplier. Coexists with the older severity label.
- 2026-05-29: Export privacy at the **Codable/model level** — `NetworkMetadata` CodingKeys omit IP/DNS/gateway/SSID/BSSID/proxy fields, so they never serialize to JSON export or on-disk history (decode as nil). Trade-off: historical results lose these after relaunch; live/current display unaffected.
- 2026-04-15: Adopt App Shell Standard (Penumbra/CropBatch) — dark mode, HSplitView with autosave, FCPToolbarButtonStyle, `UIDesignRequiresCompatibility` in Info.plist. Default accent kept as Apple blue (not brand orange) to preserve legacy visual identity. Segmented pickers replaced with FCP-button HStacks across 4 sites (dark-mode white-on-white fix).
- 2026-04-14: Lazy interface loading via SwiftUI `.task` on SettingsView — fixes 5s launch stall caused by DispatchSemaphore.wait on MainActor (see [decisions.md](decisions.md))
- 2025-12-03: Multi-server testing (Apple, Cloudflare, M-Lab) for comprehensive results
- 2025-12-02: Built-in network diagnostics (ping, traceroute, DNS) for all-in-one tool
- 2025-12-01: Native macOS app using SwiftUI for modern UI
- Export formats: PNG, CSV, JSON, PDF for flexibility
- Privacy-first: no accounts, no telemetry, data stays local

## Done for v1.1.0 (ship line — everything not listed waits for v1.2 by default)
- [ ] Release build of 1.1.0 (build 1100) built, notarized, stapled; DMG opens on a clean system
- [ ] Core flows crash-free: single test, multi-server test, network tools, LAN test, history, all four exports
- [ ] README updated with the v1.1.0 features
- [ ] appcast.xml: DMG signed (`sign_update -f` the 99-AUTH key), signature + length filled in, pushed to main; DMG attached to the GitHub v1.1.0 release
- [ ] Fresh screenshots in `03_Screenshots/`

## Blockers
- v1.1.0 DMG not yet built — the old `APP/NetworkQuality-v1.0.3/NetworkQuality-1.0.3.dmg` is stale (predates the May 29 features); rebuild as 1.1.0, then notarize and capture fresh screenshots into `03_Screenshots/`.
- SourceKit indexer shows stale "Cannot find X in scope" diagnostics — xcodebuild builds clean, cosmetic only. Xcode reindex clears it.
- This folder is a **Syncthing copy where `.git` doesn't survive sync**; if the local repo vanishes, re-attach with init → add origin → fetch → `reset --mixed origin/main` (see Claude memory `git-repo-recovery`).

---
*Updated by Claude. Source of truth for project position.*
