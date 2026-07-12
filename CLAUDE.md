# NetworkQuality

Native macOS app for comprehensive network performance testing and diagnostics —
speed tests across Apple/Cloudflare/M-Lab, bufferbloat grading, connection info,
ping/traceroute/DNS tools. Privacy-first: no accounts, no telemetry, local data only.

**Repo/git:** https://github.com/Xpycode/NetworkQuality.git (HTTPS via `gh`, account Xpycode)
> `.git` does not survive Syncthing — on a fresh Mac run the `git-bootstrap` skill
> (init → fetch → `reset --mixed origin/main` → verify) before any edit or commit.

## Tech Stack
- Swift 5.0, SwiftUI, macOS 14.0+
- Apple `networkQuality` CLI integration; Cloudflare + M-Lab NDT7 APIs
- Xcode project at `01_Project/NetworkQuality.xcodeproj` (tracked in git, no xcodegen)
- Version lives only in the pbxproj (`GENERATE_INFOPLIST_FILE = YES`); build number
  convention: `1.1.0 → 1100`

## Key Decisions (full log: docs/decisions.md)
- App Shell Standard (dark theme, HSplitView, FCP toolbar buttons); accent stays Apple blue
- Export privacy at the Codable level — identifying network fields never serialize
- Bufferbloat grade keyed on absolute added latency (ms), Waveform/DSLReports scale
- Network info read natively (`getifaddrs` + `SCDynamicStore`), no subprocesses

## State
Current position, blockers, and progress: `docs/PROJECT_STATE.md`
(Directions Index for house docs: `~/.claude/CLAUDE.md`)
