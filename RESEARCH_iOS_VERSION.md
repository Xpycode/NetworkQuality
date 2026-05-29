# Research: iOS Version of NetworkQuality

## Executive Summary

Porting NetworkQuality to iOS is **feasible but requires significant rework** due to macOS-only dependencies and iOS platform restrictions. The core SwiftUI views can largely be shared, but the networking/testing layer must be reimplemented. Key challenges include the absence of the `networkQuality` CLI on iOS, no CoreWLAN framework, and Apple's restrictive Wi-Fi APIs on iOS.

---

## Current Architecture (macOS)

The app relies on several **macOS-only** components:

| Component | macOS Framework | iOS Availability |
|---|---|---|
| Speed test (Apple) | `networkQuality` CLI tool | **Not available** |
| Wi-Fi info (SSID, RSSI, channel) | CoreWLAN | **Not available** — use `NEHotspotNetwork` (limited) |
| Network diagnostics (ping, traceroute) | Process-based CLI wrappers | **Not available** — must use Network framework |
| LAN speed testing | Bonjour/NWListener | Available (Network framework) |
| Multi-server tests (Cloudflare, M-Lab) | HTTP/WebSocket | **Fully portable** |
| UI layer | SwiftUI + AppKit bits | SwiftUI portable; replace AppKit with UIKit |
| PDF reports | AppKit-based rendering | Replace with UIKit/PDFKit |

---

## Approach 1: Native iOS App (Recommended)

### What Can Be Reused (~40-50%)
- **Models**: `NetworkQualityResult`, `HistoryModels`, `NetworkInsights` — mostly portable as-is
- **Multi-server testing**: `MultiServerTestService` (Cloudflare HTTP + M-Lab NDT7) — fully portable
- **History/export logic**: UserDefaults storage, CSV/JSON export — fully portable
- **SwiftUI views**: Most views can be adapted with `#if os(iOS)` / `#if os(macOS)` conditional compilation
- **View models**: Business logic in `NetworkQualityViewModel` is largely reusable

### What Must Be Rewritten (~50-60%)

#### 1. Speed Testing — Replace `networkQuality` CLI

The `networkQuality` CLI does not exist on iOS. Options:

- **Implement the RPM protocol yourself**: The "Responsiveness under Working Conditions" metric is an [IETF draft (draft-cpaasch-ippm-responsiveness)](https://www.ietf.org/archive/id/draft-cpaasch-ippm-responsiveness-00.html). Reference implementations exist:
  - [goresponsiveness](https://github.com/network-quality/goresponsiveness) — Go implementation
  - [network-quality/server](https://github.com/network-quality/server) — Server-side configs
  - This would be the most accurate port but is complex (~weeks of work)

- **Use M-Lab NDT7 as primary test**: The [ndt7-client-ios](https://github.com/m-lab/ndt7-client-ios) Swift library already provides download/upload speed measurement on iOS. This is the easiest path but loses Apple's RPM metric.

- **HTTP-based throughput test**: Like the existing Cloudflare test in `MultiServerTestService`, run timed HTTP GET/POST transfers to measure speed. Simple but lacks responsiveness measurement.

- **Hybrid approach** (recommended): Use NDT7 + Cloudflare for throughput, and implement a simplified latency-under-load test for a responsiveness approximation.

#### 2. Wi-Fi Metadata — Replace CoreWLAN

iOS severely restricts Wi-Fi information access. The replacement:

- **`NEHotspotNetwork.fetchCurrent()`** (iOS 14+): Provides SSID and BSSID only
  - Requires the `com.apple.developer.networking.wifi-info` entitlement
  - Requires one of: CoreLocation authorization, active VPN, NEHotspotConfiguration, or NEDNSSettingsManager
  - **Does NOT provide**: signal strength (RSSI), noise, channel, band, link speed, security type

- **What's lost on iOS**: Signal strength, noise level, channel, band (2.4/5/6 GHz), link speed, security type — none of these are accessible to third-party iOS apps

- **Note**: `CNCopyCurrentNetworkInfo` is deprecated as of iOS 26 SDK. Use `NEHotspotNetwork.fetchCurrent()` instead.

#### 3. Network Diagnostics — Replace CLI Tools

The macOS app wraps `ping` and `traceroute` CLI tools via `Process`. On iOS:

- **Ping**: Use `NWConnection` with UDP/ICMP or a library like [SwiftyPing](https://github.com/samirank/SwiftyPing). Note: raw ICMP sockets require special entitlements on iOS.
- **Traceroute**: Implement using UDP probes with incrementing TTL via `NWConnection`. No built-in iOS equivalent.
- **DNS lookup**: Use `nw_connection_t` with DNS service discovery, or `CFHost`/`getaddrinfo`.

#### 4. UI Adaptations

- Replace `NavigationSplitView` sidebar pattern with tab-based navigation (`TabView`) for iPhone
- iPad can keep sidebar layout via `NavigationSplitView`
- Replace AppKit share sheets (`NSSharingServicePicker`) with `UIActivityViewController`
- Replace `NSImage` rendering with `UIImage` for share cards
- Adapt `GeoTracerouteView` MapKit usage (largely compatible)
- Replace `NSPasteboard` with `UIPasteboard`

#### 5. PDF Report

Replace AppKit-based PDF rendering with:
- `UIGraphicsPDFRenderer` (UIKit)
- Or render SwiftUI views to PDF using `ImageRenderer` (iOS 16+)

---

## Approach 2: iOS Settings Diagnostics (No App Needed)

For users who just want to test responsiveness on an iPhone/iPad **without building an app**:

1. Install the **Wi-Fi Performance Diagnostics profile** from your Apple Developer account
2. Go to **Settings > Wi-Fi > tap (i) next to your network > Diagnostics**
3. Tap **Test** next to Responsiveness

This provides Apple's official RPM test on iOS but requires a developer account and offers no history, export, or multi-server comparison features.

---

## Approach 3: Multiplatform Xcode Project

The recommended project setup:

```
NetworkQuality/
├── Shared/                    # Cross-platform code
│   ├── Models/                # All models (reuse as-is)
│   ├── Services/
│   │   ├── Protocols/         # Abstract service protocols
│   │   ├── CloudflareTestService.swift    # Shared
│   │   ├── MLab NDT7Service.swift         # Shared
│   │   └── GeoIPService.swift             # Shared
│   ├── ViewModels/            # Shared business logic
│   └── Views/                 # Shared SwiftUI views
├── macOS/                     # macOS-specific
│   ├── Services/
│   │   ├── AppleNetworkQualityRunner.swift  # CLI wrapper
│   │   ├── CoreWLANMetadata.swift           # Wi-Fi info
│   │   └── CLINetworkTools.swift            # ping/traceroute
│   └── Views/                 # macOS-specific UI
├── iOS/                       # iOS-specific
│   ├── Services/
│   │   ├── iOSSpeedTestService.swift    # NDT7/HTTP-based
│   │   ├── iOSWiFiMetadata.swift        # NEHotspotNetwork
│   │   └── iOSNetworkTools.swift        # NWConnection-based
│   └── Views/                 # iOS-specific UI (TabView, etc.)
```

---

## Estimated Effort

| Task | Effort |
|---|---|
| Project restructure (multiplatform) | 1-2 days |
| Speed test service for iOS (NDT7-based) | 3-5 days |
| RPM/responsiveness implementation (if desired) | 1-2 weeks |
| Wi-Fi metadata (NEHotspotNetwork) | 1 day |
| Network tools (ping/traceroute/DNS) | 3-5 days |
| UI adaptations (iPhone + iPad layouts) | 3-5 days |
| PDF report (UIKit renderer) | 1 day |
| Share card adaptations | 1-2 days |
| Testing and polish | 3-5 days |
| **Total (without RPM)** | **~2-4 weeks** |
| **Total (with full RPM)** | **~4-6 weeks** |

---

## Key iOS Limitations to Accept

1. **No Wi-Fi signal strength (RSSI)** — Apple does not expose this on iOS
2. **No Wi-Fi channel/band/security info** — CoreWLAN is macOS-only
3. **No Apple networkQuality RPM** — must implement independently or approximate
4. **SSID requires location permission** — users must grant location access
5. **No LAN speed test discovery** unless both devices run the app (Bonjour works on iOS)
6. **ICMP ping requires entitlement** — may need `com.apple.developer.networking.multicast` or use UDP-based alternatives

---

## Existing Open-Source References

- [ndt7-client-ios](https://github.com/m-lab/ndt7-client-ios) — M-Lab's iOS speed test framework (Apache 2.0)
- [goresponsiveness](https://github.com/network-quality/goresponsiveness) — Reference RPM implementation in Go
- [network-quality/server](https://github.com/network-quality/server) — Server configs for networkQuality tests
- [OpenSpeedTest](https://github.com/openspeedtest/Speed-Test) — HTML5 speed test (works in iOS Safari)
- [SpeedChecker SDK](https://github.com/speedchecker/speedchecker-sdk-ios) — Commercial iOS speed test SDK

---

## Recommendation

The most practical path is **Approach 1 with the hybrid speed test** (NDT7 + Cloudflare + simplified latency-under-load). This provides:

- Real download/upload speed measurements
- Multi-server comparison (already built)
- A reasonable responsiveness approximation
- Achievable in ~2-4 weeks

Full RPM protocol implementation would make the app unique in the App Store but adds significant complexity. Consider it as a v2 feature.

---

## Sources

- [IETF Responsiveness under Working Conditions](https://www.ietf.org/archive/id/draft-cpaasch-ippm-responsiveness-00.html)
- [Apple NWPathMonitor Documentation](https://developer.apple.com/documentation/network/nwpathmonitor)
- [NEHotspotNetwork Documentation](https://developer.apple.com/documentation/networkextension/nehotspotnetwork)
- [WWDC21: Reduce network delays for your app](https://developer.apple.com/videos/play/wwdc2021/10239/)
- [TidBITS: Apple's networkQuality Tool](https://tidbits.com/2022/04/22/use-apples-networkquality-tool-to-test-internet-responsiveness/)
- [Speediness (Sindre Sorhus)](https://sindresorhus.com/speediness) — confirms iOS limitation
- [The Sad State of Wi-Fi APIs in Apple Platforms](https://medium.com/@istumbler/the-sad-state-of-wi-fi-apis-in-apple-platforms-943893be17a2)
