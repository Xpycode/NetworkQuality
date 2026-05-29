# Project State

> **Size limit: <100 lines.** This is a digest, not an archive.

## Identity
- **Project:** NetworkQuality
- **One-liner:** Native macOS app for comprehensive network performance testing and diagnostics
- **Started:** 2025-12-01

## Current Position
- **Phase:** polish
- **Focus:** Connection Info diagnostics shipped to `main` (PRs #1 & #2 merged): local+public IPv6, dual-stack badge, gateway/subnet/MTU/DNS, VPN/proxy detection, bufferbloat letter grade, live pre-test Connection Info panel, and privacy-scrubbed exports. App Shell history-toolbar icons + light-mode share cards also landed. Still pending from v1.0.3: notarization + fresh screenshots, dark-mode color audit (477 refs).
- **Status:** in progress
- **Last updated:** 2026-05-29

## Progress
```
[#################---] 85% - v1.0.3 shell migration + new Connection Info diagnostics merged; dark-mode audit & notarization pending
```

| Phase | Status | Notes |
|-------|--------|-------|
| Discovery | done | — |
| Planning | done | — |
| Implementation | done | All features shipped |
| Polish | **active** | Shell migration to Penumbra standard — Phase 4–6 pending |
| Shipping | paused | v1.0.3 DMG ready for notarization; v1.0.2 is current public release |

## Tech Stack
- Swift 5.0, SwiftUI
- macOS 14.0+ native
- Apple `networkQuality` CLI integration
- Cloudflare/M-Lab APIs for multi-server testing

## Active Decisions
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

## Blockers
- Awaiting user: notarize `APP/NetworkQuality-v1.0.3/NetworkQuality-1.0.3.dmg`, capture fresh screenshots into `03_Screenshots/`.
- SourceKit indexer shows stale "Cannot find X in scope" diagnostics — xcodebuild builds clean, cosmetic only. Xcode reindex clears it.
- This folder is a **Syncthing copy where `.git` doesn't survive sync**; if the local repo vanishes, re-attach with init → add origin → fetch → `reset --mixed origin/main` (see Claude memory `git-repo-recovery`).

---
*Updated by Claude. Source of truth for project position.*
