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

---

## Essential

### Menu Bar Live Speed
Persistent upload/download throughput display between tests. Makes the app a useful utility that runs continuously.

### Scheduled Background Testing
- Configure automatic tests (hourly/daily)
- Log results for ISP performance documentation
- Essential for proving throttling or demanding service credits

### CSV Export
Spreadsheet-friendly export format for history data. (JSON already available)

### PDF Report
Branded PDF report with:
- Test results
- Insights and recommendations
- Historical trends

---

## Medium Priority

### Notification Alerts
- Alert when speed drops below configured threshold
- Connection lost notification
- Speed recovered after outage

### Network Troubleshooting Tools
Wrap common diagnostic tools in a friendly UI:
- Ping (with visualization)
- Traceroute
- DNS lookup

### VPN Comparison Mode
Run tests with VPN on vs. off and highlight the difference. Helps users detect ISP throttling.

---

## Longer Term

### LAN Speed Testing
Simple local network speed test between Macs without server setup. Highly requested but poorly served by existing apps.

### Multi-Server Testing
Test against multiple infrastructures in one session:
- Apple (networkQuality)
- Cloudflare
- M-Lab (NDT7)

Helps identify routing issues or server-specific throttling.

### Per-Application Bandwidth Attribution
Show which apps use bandwidth during tests. Would require additional permissions (Network Extension or similar).

### Geographic Connection Visualization
Map view showing where network traffic routes through, inspired by GlassWire.
