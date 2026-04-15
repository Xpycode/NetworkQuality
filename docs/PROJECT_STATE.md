# Project State

> **Size limit: <100 lines.** This is a digest, not an archive.

## Identity
- **Project:** NetworkQuality
- **One-liner:** Native macOS app for comprehensive network performance testing and diagnostics
- **Started:** 2025-12-01

## Current Position
- **Phase:** polish
- **Focus:** App Shell Standard migration — Phases 1–3 + picker sweep landed in v1.0.3 (committed, pushed, DMG built). Awaiting: user notarization + screenshots, then Phase 4–6 (remaining toolbar FCP styling + dark-mode audit of 477 color refs + verification).
- **Status:** in progress
- **Last updated:** 2026-04-15

## Progress
```
[################----] 80% - v1.0.3 migration mid-flight (shell + pickers done, dark-mode audit pending)
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
- 2026-04-15: Adopt App Shell Standard (Penumbra/CropBatch) — dark mode, HSplitView with autosave, FCPToolbarButtonStyle, `UIDesignRequiresCompatibility` in Info.plist. Default accent kept as Apple blue (not brand orange) to preserve legacy visual identity. Segmented pickers replaced with FCP-button HStacks across 4 sites (dark-mode white-on-white fix).
- 2026-04-14: Lazy interface loading via SwiftUI `.task` on SettingsView — fixes 5s launch stall caused by DispatchSemaphore.wait on MainActor (see [decisions.md](decisions.md))
- 2025-12-03: Multi-server testing (Apple, Cloudflare, M-Lab) for comprehensive results
- 2025-12-02: Built-in network diagnostics (ping, traceroute, DNS) for all-in-one tool
- 2025-12-01: Native macOS app using SwiftUI for modern UI
- Export formats: PNG, CSV, JSON, PDF for flexibility
- Privacy-first: no accounts, no telemetry, data stays local

## Blockers
- Awaiting user: notarize `APP/NetworkQuality-v1.0.3/NetworkQuality-1.0.3.dmg`, capture fresh screenshots into `03_Screenshots/`.
- SourceKit indexer shows stale "Cannot find X in scope" diagnostics for the new `Theme/` files — xcodebuild builds clean, cosmetic only. Xcode reindex clears it.

---
*Updated by Claude. Source of truth for project position.*
