# Changelog

## 2025-12-02

### UI-5: Shareable Result Cards

#### New Features
- **Share Button**: Added share menu to Results view with multiple options
  - Copy Image: Copies a beautiful result card to clipboard
  - Save Image: Saves result card as PNG file
  - Share Text: Shares formatted text summary via macOS share sheet
- **Result Card Design**: Visually appealing card for social sharing
  - Header with gradient (blue to purple) and overall quality rating
  - Download/Upload speeds in colored metric boxes
  - Responsiveness (RPM) and Latency with rating badges
  - Network info section showing connection type, WiFi name, band, signal quality
  - Footer with timestamp and app branding
  - Rendered at 2x scale (retina quality)

#### Files Added
- `ShareableResultCardView.swift`: Card UI, image rendering, ShareService, ShareMenuButton

---

### UI-4: Rich Network Metadata and Location Permission

#### New Features
- **Network Metadata Capture**: Store detailed connection info with each test
  - Connection type (WiFi/Ethernet)
  - Interface name, local IP address
  - WiFi details: RSSI signal strength, channel, band (2.4/5/6 GHz), link speed, security type
- **SSID Access with Location Permission**:
  - "Enable WiFi Name" button to request location permission
  - Custom privacy message: "No location data is collected, stored, or shared"
  - System dialog shows explanation from Info.plist
- **Connection Info Section**: Shows in Results (both Insights and Raw Data tabs) and History detail view
  - Signal quality color-coded (Excellent/Good/Fair/Weak/Poor)
  - Displays all WiFi metrics in organized grid

#### Files Added
- `NetworkMetadata.swift`: NetworkMetadata model, NetworkInfoService, LocationPermissionManager

---

### UI-3: Bufferbloat Visualization and Insights Improvements

#### New Features
- **Bufferbloat Visualization**: Visual comparison of idle vs loaded latency
  - Bar chart showing latency increase under load
  - Severity rating (Minimal/Moderate/Significant/Severe) with color coding
  - Latency multiplier display (e.g., "5.6× slower")
  - Expandable "What is bufferbloat?" educational section
- **RPM Rating Mode Toggle**: Switch between Practical and IETF thresholds in Settings
  - Practical: Real-world thresholds for typical home networks
  - IETF: Official RFC thresholds from draft-ietf-ippm-responsiveness
- **Clickable History Rows**: Open full detail sheet with insights for any past test
- **Clickable Insight Summary**: Main view summary navigates to Results tab
- **Fully Clickable Expandable Sections**: "What is bufferbloat?" and "Verbose Output" headers are now fully clickable (not just the chevron)

#### Bug Fixes
- Fixed "Publishing changes from within view updates" warning by throttling objectWillChange
- Fixed animation stutter by using TimelineView for smooth rotation

#### Files Added
- `NetworkInsights.swift`: Plain-language explanations, RPM thresholds, speed capabilities
- `InsightsView.swift`: Full insights UI with bufferbloat visualization

---

## 2025-12-01

### UI-2: Speed Unit Toggle, Progress Indicator, and UI Polish

#### New Features
- **Speed Unit Toggle**: Added MB/s and Mbit/s toggle in toolbar, available across all views
  - Uses `SpeedUnit` enum with automatic unit scaling (KB/s, MB/s, GB/s or Kbit/s, Mbit/s, Gbit/s)
  - Persisted via `@AppStorage("speedUnit")`
- **Test Mode Toggle**: Added Parallel/Sequential picker below start button on main screen
- **Indeterminate Progress Animation**: Replaced percentage-based progress with smooth rotating arc
  - Shows elapsed time in center of button during test
  - Continuous rotation avoids issues with unpredictable test duration
- **Latency in History**: History view now shows Latency alongside Download, Upload, and RPM

#### UI Improvements
- Moved speed unit toggle to toolbar center (`.principal` placement)
- Centered main UI elements (gauges, button, mode picker) with Spacers
- Stats row (Latency, RPM) now fixed at bottom with reserved height - no layout shift
- Reduced minimum window height from 600 to 450 pixels
- Removed Speed Graph view (unnecessary feature)

#### Bug Fixes
- **Disabled App Sandbox**: Set `ENABLE_APP_SANDBOX = NO` to allow `networkQuality` and `script` subprocess execution
- Fixed StatPill to show both label and value text

#### Research Notes
- Investigated progress indicator UX patterns from Speedtest.net, Fast.com, and UX best practices
- Determinate progress only appropriate when completion can be tracked
- Speed tests use indeterminate animation + current measurement as feedback
- Line-count based progress unreliable (varies with network speed and test mode)

---

### UI-1: Compact UI Redesign and Cancellation Fix (earlier session)

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
