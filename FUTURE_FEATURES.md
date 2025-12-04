# Future Features

Feature roadmap based on competitive analysis of macOS speed test apps.

## Completed

### ✅ Bufferbloat Visualization
Show idle vs. loaded latency graphically - the "before/after" that explains WHY RPM matters.
- Bar chart comparing idle vs loaded latency
- Severity rating with color coding
- Educational "What is bufferbloat?" section

### ✅ Rich History Metadata
Store additional context with each test:
- ✅ WiFi network name (SSID) - requires location permission
- ✅ Connection type (WiFi/Ethernet)
- ✅ IP address
- ✅ Signal strength (RSSI), channel, band, link speed, security
- ❌ ISP name (would need external API)
- ❌ Geographic server location (would need external API)

### ✅ Plain-Language Insights
- RPM explanations with activity impact ratings
- "What can you do with this speed" capability grid
- RPM Rating Mode toggle (Practical vs IETF thresholds)

### ✅ Shareable Result Cards
Generate image cards for social media sharing with:
- Speed results (download/upload)
- RPM rating with badge
- Network info (connection type, WiFi name, signal quality)
- Timestamp and app branding
- Copy to clipboard, save as PNG, or share text summary

### ✅ CSV Export
Spreadsheet-friendly export format for history data:
- Toggle between CSV and JSON in export dialog
- All metrics: speeds, RPM, latency, network metadata
- WiFi details: SSID, band, channel, signal quality
- Proper escaping for special characters

### ✅ Network Troubleshooting Tools
Wrap common diagnostic tools in a friendly UI:
- Ping with real-time stats (min/avg/max/loss)
- Traceroute with visual hop display
- DNS lookup with multiple record types (A, AAAA, CNAME, MX, TXT, NS)

### ✅ Multi-Server Testing
Test against multiple infrastructures in one session:
- Apple (networkQuality)
- Cloudflare (HTTP-based speed test)
- M-Lab NDT7 (WebSocket protocol)
- Visual comparison charts and summary table
- Helps identify routing issues or server-specific throttling

### ✅ Multi-Server Share Card
Shareable comparison card for multi-server results:
- Orange/amber gradient header (speed/energy theme)
- Provider ranking with crown for fastest
- Download, upload, latency for each provider
- Variance analysis (consistent/minor/significant)
- Copy image, save PNG, or copy text summary

### ✅ Geographic Connection Visualization
Map view showing where network traffic routes through:
- Traceroute with GeoIP lookup for each hop
- Interactive map with route polylines
- Color-coded markers (start/hops/destination)
- Popular hosts quick-select

### ✅ Multi-Server History
Save multi-server comparison results over time:
- Store all provider results together as a comparison set
- View historical comparisons to track provider performance
- Persistent storage with UserDefaults

### ✅ Network Tools History
Save diagnostic tool results for later review:
- Store ping sessions with statistics
- Save traceroute paths for comparison
- Keep DNS lookup history
- Filter by tool type

---

## High Priority

### LAN Speed Testing
Simple local network speed test between Macs without server setup. Highly requested but poorly served by existing apps.

---

## Lower Priority

### Menu Bar Live Speed
Persistent upload/download throughput display between tests. Makes the app a useful utility that runs continuously.

### Scheduled Background Testing
- Configure automatic tests (hourly/daily)
- Log results for ISP performance documentation
- Essential for proving throttling or demanding service credits

### PDF Report
Branded PDF report with:
- Test results
- Insights and recommendations
- Historical trends

### Notification Alerts
- Alert when speed drops below configured threshold
- Connection lost notification
- Speed recovered after outage

### VPN Comparison Mode
Run tests with VPN on vs. off and highlight the difference. Helps users detect ISP throttling.

### Per-Application Bandwidth Attribution
Show which apps use bandwidth during tests. Would require additional permissions (Network Extension or similar).

### Network Tools Share Cards
Generate shareable cards for diagnostic results:
- Ping summary card with min/avg/max/loss stats
- Traceroute visualization showing hop path
- DNS lookup results with record details
