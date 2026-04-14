# Project State

> **Size limit: <100 lines.** This is a digest, not an archive.

## Identity
- **Project:** NetworkQuality
- **One-liner:** Native macOS app for comprehensive network performance testing and diagnostics
- **Started:** 2025-12-01

## Current Position
- **Phase:** done
- **Focus:** v1.0.2 shipped — launch perf fix landed (3–5s → ~197ms on M4 Pro), monitoring
- **Status:** ready
- **Last updated:** 2026-04-14

## Progress
```
[####################] 100% - v1.0.2 released, all core features complete
```

| Phase | Status | Notes |
|-------|--------|-------|
| Discovery | done | — |
| Planning | done | — |
| Implementation | done | All features shipped |
| Polish | done | Launch perf fix in v1.0.2 (Apr 14, 2026) |
| Shipping | **active** | v1.0.2 on GitHub Releases |

## Tech Stack
- Swift 5.0, SwiftUI
- macOS 14.0+ native
- Apple `networkQuality` CLI integration
- Cloudflare/M-Lab APIs for multi-server testing

## Active Decisions
- 2026-04-14: Lazy interface loading via SwiftUI `.task` on SettingsView — fixes 5s launch stall caused by DispatchSemaphore.wait on MainActor (see [decisions.md](decisions.md))
- 2025-12-03: Multi-server testing (Apple, Cloudflare, M-Lab) for comprehensive results
- 2025-12-02: Built-in network diagnostics (ping, traceroute, DNS) for all-in-one tool
- 2025-12-01: Native macOS app using SwiftUI for modern UI
- Export formats: PNG, CSV, JSON, PDF for flexibility
- Privacy-first: no accounts, no telemetry, data stays local

## Blockers
None. Project is in maintenance mode.

---
*Updated by Claude. Source of truth for project position.*
