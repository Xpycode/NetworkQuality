# Changelog

## 2024-12-01

### UI-1: Compact UI Redesign and Cancellation Fix

#### UI Changes
- Removed redundant/duplicate UI elements:
  - `QuickStatsView` (duplicated speed gauge data)
  - `TestInfoView` (rarely needed configuration display)
  - `ResponsivenessGaugeView` and `LatencyGaugeView` (replaced with compact pills)
  - `LatencyComparisonView` and `ResponsivenessHistoryView` (no data available with text parsing)
- Added compact `StatPill` components showing latency, RPM, and interface after test completes
- Moved start button from toolbar to center of view as large circular button (80px)
- Button transforms into spinning progress indicator when test is running
- Reduced speed gauge size from 180px to 160px
- Simplified toolbar to only show Clear button

#### Bug Fixes
- Added `wasCancelled` flag to handle test cancellation gracefully
- Cancelled tests no longer trigger error alert

---

### Initial Commit: Real-time Speed Updates

#### Features
- Fixed UI responsiveness during speed tests by replacing blocking `waitUntilExit()` with async `terminationHandler` and `withCheckedContinuation`
- Added real-time download/upload speed display during tests using pseudo-TTY wrapper (`script` command) to capture `networkQuality` progress output
- Added thread-safe `DataAccumulator` class for concurrent output capture
- Forward service `objectWillChange` to ViewModel for proper SwiftUI updates
- Parse text summary output instead of JSON to enable live progress

#### Technical Details
- Service uses `/usr/bin/script -q /dev/null /bin/sh -c "networkQuality ..."` to allocate pseudo-TTY
- Progress output parsed with regex for "Downlink: X.XX Mbps" and "Uplink: X.XX Mbps" patterns
- Final results parsed from text summary (Downlink capacity, Uplink capacity, Responsiveness, Idle Latency)
