import SwiftUI

/// Rating mode for RPM thresholds
enum RPMRatingMode: String, CaseIterable {
    case practical = "Practical"
    case ietf = "IETF Standard"

    var description: String {
        switch self {
        case .practical:
            return "Real-world thresholds based on typical home network experience"
        case .ietf:
            return "Official IETF RFC thresholds (stricter, optimized for low-latency networks)"
        }
    }
}

/// Provides plain-language explanations of network quality metrics
struct NetworkInsights {

    // MARK: - RPM (Responsiveness) Insights

    struct ResponsivenessInsight {
        let rating: ResponsivenessRating
        let headline: String
        let explanation: String
        let activities: [ActivityStatus]
        let recommendation: String?
    }

    enum ResponsivenessRating: String {
        case poor = "Poor"
        case fair = "Fair"
        case good = "Good"
        case excellent = "Excellent"

        var color: Color {
            switch self {
            case .poor: return .red
            case .fair: return .orange
            case .good: return .blue
            case .excellent: return .green
            }
        }

        var icon: String {
            switch self {
            case .poor: return "exclamationmark.triangle.fill"
            case .fair: return "minus.circle.fill"
            case .good: return "checkmark.circle.fill"
            case .excellent: return "star.circle.fill"
            }
        }
    }

    static func responsivenessInsight(rpm: Int, mode: RPMRatingMode = .practical) -> ResponsivenessInsight {
        switch mode {
        case .practical:
            return practicalResponsivenessInsight(rpm: rpm)
        case .ietf:
            return ietfResponsivenessInsight(rpm: rpm)
        }
    }

    // MARK: - IETF Standard Thresholds
    // Based on draft-ietf-ippm-responsiveness
    // Excellent: 6000+ RPM (≤10ms), Good: 1000+ (≤60ms), Fair: 300+ (≤200ms), Poor: <300

    private static func ietfResponsivenessInsight(rpm: Int) -> ResponsivenessInsight {
        switch rpm {
        case ..<300:
            return ResponsivenessInsight(
                rating: .poor,
                headline: "Poor responsiveness",
                explanation: "Round-trip time exceeds 200ms under load. Per IETF standards, this indicates significant bufferbloat or network congestion.",
                activities: [
                    .init(name: "Video calls", status: .poor, detail: "Noticeable delay"),
                    .init(name: "Gaming", status: .poor, detail: "High latency"),
                    .init(name: "Web browsing", status: .fair, detail: "Sluggish"),
                    .init(name: "Streaming", status: .good, detail: "Buffered, works OK")
                ],
                recommendation: "Enable SQM (Smart Queue Management) on your router to reduce bufferbloat."
            )
        case 300..<1000:
            return ResponsivenessInsight(
                rating: .fair,
                headline: "Fair responsiveness",
                explanation: "Round-trip time is 60-200ms under load. Acceptable for most uses but not optimal for real-time applications.",
                activities: [
                    .init(name: "Video calls", status: .fair, detail: "Minor delays possible"),
                    .init(name: "Gaming", status: .fair, detail: "Some lag"),
                    .init(name: "Web browsing", status: .good, detail: "Responsive"),
                    .init(name: "Streaming", status: .excellent, detail: "No issues")
                ],
                recommendation: "Good for everyday use. QoS settings may improve real-time applications."
            )
        case 1000..<6000:
            return ResponsivenessInsight(
                rating: .good,
                headline: "Good responsiveness",
                explanation: "Round-trip time is 10-60ms under load. Meets IETF 'Good' threshold for responsive networks.",
                activities: [
                    .init(name: "Video calls", status: .excellent, detail: "Clear and responsive"),
                    .init(name: "Gaming", status: .good, detail: "Low latency"),
                    .init(name: "Web browsing", status: .excellent, detail: "Snappy"),
                    .init(name: "Streaming", status: .excellent, detail: "Flawless")
                ],
                recommendation: nil
            )
        default: // 6000+
            return ResponsivenessInsight(
                rating: .excellent,
                headline: "Excellent responsiveness",
                explanation: "Round-trip time is under 10ms even under load. This exceeds IETF 'Excellent' threshold — optimal for all real-time applications.",
                activities: [
                    .init(name: "Video calls", status: .excellent, detail: "Professional quality"),
                    .init(name: "Gaming", status: .excellent, detail: "Competitive ready"),
                    .init(name: "Web browsing", status: .excellent, detail: "Instant"),
                    .init(name: "Streaming", status: .excellent, detail: "Perfect")
                ],
                recommendation: nil
            )
        }
    }

    // MARK: - Practical Thresholds
    // Based on real-world home network experience

    private static func practicalResponsivenessInsight(rpm: Int) -> ResponsivenessInsight {
        // RPM thresholds based on Apple's guidance and real-world experience:
        // - Streaming & browsing work fine at almost any RPM (they're buffered)
        // - Video calls need ~200+ RPM to be usable
        // - Competitive gaming benefits from 800+ RPM
        // - Most home users are fine with 300-600 RPM
        switch rpm {
        case ..<200:
            return ResponsivenessInsight(
                rating: .poor,
                headline: "High latency under load",
                explanation: "Your network slows down significantly when busy. Video calls may freeze during downloads, and interactive apps feel sluggish. Streaming and browsing still work fine since they buffer.",
                activities: [
                    .init(name: "Video calls", status: .poor, detail: "May freeze when network is busy"),
                    .init(name: "Gaming", status: .poor, detail: "Noticeable lag spikes"),
                    .init(name: "Web browsing", status: .good, detail: "Works, pages may load slowly"),
                    .init(name: "Streaming", status: .good, detail: "Works fine (buffered)")
                ],
                recommendation: "This is usually caused by bufferbloat. Consider enabling SQM (Smart Queue Management) on your router, or look for routers with good queue management like eero or OpenWrt."
            )
        case 200..<400:
            return ResponsivenessInsight(
                rating: .fair,
                headline: "Typical home network",
                explanation: "Your network handles everyday tasks well. Video calls and browsing work fine. You might notice brief slowdowns if someone starts a large download during a video call.",
                activities: [
                    .init(name: "Video calls", status: .good, detail: "Works well for most calls"),
                    .init(name: "Gaming", status: .fair, detail: "Casual gaming fine, competitive may lag"),
                    .init(name: "Web browsing", status: .good, detail: "Responsive"),
                    .init(name: "Streaming", status: .excellent, detail: "No issues")
                ],
                recommendation: "Your network is fine for typical use. For smoother video calls during heavy downloads, your router's QoS settings may help."
            )
        case 400..<800:
            return ResponsivenessInsight(
                rating: .good,
                headline: "Good responsiveness",
                explanation: "Your network stays responsive even when multiple people are online. Video calls remain stable during other network activity.",
                activities: [
                    .init(name: "Video calls", status: .excellent, detail: "Stable and clear"),
                    .init(name: "Gaming", status: .good, detail: "Good for most games"),
                    .init(name: "Web browsing", status: .excellent, detail: "Snappy"),
                    .init(name: "Streaming", status: .excellent, detail: "No buffering")
                ],
                recommendation: nil
            )
        case 800..<1500:
            return ResponsivenessInsight(
                rating: .excellent,
                headline: "Very responsive",
                explanation: "Your network maintains low latency even under heavy load. Great for households with multiple simultaneous video calls or competitive gaming.",
                activities: [
                    .init(name: "Video calls", status: .excellent, detail: "Crystal clear"),
                    .init(name: "Gaming", status: .excellent, detail: "Low latency"),
                    .init(name: "Web browsing", status: .excellent, detail: "Instant"),
                    .init(name: "Streaming", status: .excellent, detail: "Flawless")
                ],
                recommendation: nil
            )
        default: // 1500+
            return ResponsivenessInsight(
                rating: .excellent,
                headline: "Excellent responsiveness",
                explanation: "Outstanding network quality. Your connection maintains minimal latency even when fully saturated — ideal for competitive gaming and professional video conferencing.",
                activities: [
                    .init(name: "Video calls", status: .excellent, detail: "Professional quality"),
                    .init(name: "Gaming", status: .excellent, detail: "Competitive ready"),
                    .init(name: "Web browsing", status: .excellent, detail: "Instant"),
                    .init(name: "Streaming", status: .excellent, detail: "4K+ simultaneous")
                ],
                recommendation: nil
            )
        }
    }

    // MARK: - Speed Capability Insights

    struct SpeedInsight {
        let headline: String
        let capabilities: [ActivityCapability]
        let limitations: [String]
    }

    struct ActivityCapability {
        let activity: String
        let supported: Bool
        let detail: String
        let icon: String
    }

    struct ActivityStatus: Identifiable {
        let id = UUID()
        let name: String
        let status: Status
        let detail: String

        enum Status {
            case poor, fair, good, excellent

            var color: Color {
                switch self {
                case .poor: return .red
                case .fair: return .orange
                case .good: return .blue
                case .excellent: return .green
                }
            }

            var icon: String {
                switch self {
                case .poor: return "xmark.circle.fill"
                case .fair: return "minus.circle.fill"
                case .good: return "checkmark.circle.fill"
                case .excellent: return "star.circle.fill"
                }
            }
        }
    }

    static func speedInsight(downloadMbps: Double, uploadMbps: Double) -> SpeedInsight {
        var capabilities: [ActivityCapability] = []
        var limitations: [String] = []

        // SD Streaming (3 Mbps)
        capabilities.append(ActivityCapability(
            activity: "SD Streaming",
            supported: downloadMbps >= 3,
            detail: downloadMbps >= 3 ? "Works" : "May buffer",
            icon: "play.tv"
        ))

        // HD Streaming (8 Mbps)
        capabilities.append(ActivityCapability(
            activity: "HD Streaming",
            supported: downloadMbps >= 8,
            detail: downloadMbps >= 8 ? "Smooth playback" : "May need to lower quality",
            icon: "tv"
        ))

        // 4K Streaming (25 Mbps)
        let supports4K = downloadMbps >= 25
        capabilities.append(ActivityCapability(
            activity: "4K Streaming",
            supported: supports4K,
            detail: supports4K ? "Full quality" : "Not enough bandwidth",
            icon: "4k.tv"
        ))

        // Video calls (upload matters)
        let videoCallQuality: String
        let supportsVideoCalls: Bool
        if uploadMbps >= 3 && downloadMbps >= 3 {
            supportsVideoCalls = true
            if uploadMbps >= 10 {
                videoCallQuality = "HD quality, group calls"
            } else {
                videoCallQuality = "Good for 1-on-1 calls"
            }
        } else {
            supportsVideoCalls = uploadMbps >= 1.5
            videoCallQuality = supportsVideoCalls ? "Audio only recommended" : "Poor quality expected"
        }
        capabilities.append(ActivityCapability(
            activity: "Video Calls",
            supported: supportsVideoCalls,
            detail: videoCallQuality,
            icon: "video"
        ))

        // Gaming (needs low latency more than speed, but 3+ Mbps helps)
        capabilities.append(ActivityCapability(
            activity: "Online Gaming",
            supported: downloadMbps >= 3,
            detail: downloadMbps >= 3 ? "Speed OK (latency matters more)" : "May lag",
            icon: "gamecontroller"
        ))

        // Work from home
        let wfhSupported = downloadMbps >= 25 && uploadMbps >= 5
        capabilities.append(ActivityCapability(
            activity: "Work From Home",
            supported: wfhSupported,
            detail: wfhSupported ? "Video + cloud apps" : "May struggle with video meetings",
            icon: "laptopcomputer"
        ))

        // Large downloads
        let downloadTime1GB = 1024 * 8 / downloadMbps / 60 // minutes
        capabilities.append(ActivityCapability(
            activity: "Large Downloads",
            supported: downloadMbps >= 50,
            detail: String(format: "1GB in ~%.0f min", downloadTime1GB),
            icon: "arrow.down.doc"
        ))

        // Multiple devices
        let deviceEstimate = Int(downloadMbps / 25) // rough estimate: 25 Mbps per active device
        if deviceEstimate < 2 {
            limitations.append("May struggle with multiple active devices")
        }

        // Build headline
        let headline: String
        switch downloadMbps {
        case ..<10:
            headline = "Basic browsing and SD streaming"
        case 10..<25:
            headline = "Good for HD streaming and video calls"
        case 25..<100:
            headline = "Handles most household needs"
        case 100..<500:
            headline = "Fast connection for multiple users"
        default:
            headline = "Excellent speeds for any activity"
        }

        return SpeedInsight(
            headline: headline,
            capabilities: capabilities,
            limitations: limitations
        )
    }

    // MARK: - Combined Network Quality Summary

    struct NetworkQualitySummary {
        let overallRating: OverallRating
        let headline: String
        let speedSummary: String
        let responsivenessSummary: String
        let topRecommendation: String?
    }

    enum OverallRating {
        case poor, fair, good, excellent

        var label: String {
            switch self {
            case .poor: return "Poor"
            case .fair: return "Fair"
            case .good: return "Good"
            case .excellent: return "Excellent"
            }
        }

        var color: Color {
            switch self {
            case .poor: return .red
            case .fair: return .orange
            case .good: return .blue
            case .excellent: return .green
            }
        }
    }

    static func overallSummary(downloadMbps: Double, uploadMbps: Double, rpm: Int?, mode: RPMRatingMode = .practical) -> NetworkQualitySummary {
        let speedScore: Int
        switch downloadMbps {
        case ..<10: speedScore = 1
        case 10..<50: speedScore = 2
        case 50..<200: speedScore = 3
        default: speedScore = 4
        }

        let rpmScore: Int
        if let rpm = rpm {
            switch mode {
            case .practical:
                switch rpm {
                case ..<200: rpmScore = 1
                case 200..<400: rpmScore = 2
                case 400..<800: rpmScore = 3
                default: rpmScore = 4
                }
            case .ietf:
                switch rpm {
                case ..<300: rpmScore = 1
                case 300..<1000: rpmScore = 2
                case 1000..<6000: rpmScore = 3
                default: rpmScore = 4
                }
            }
        } else {
            rpmScore = speedScore // If no RPM, assume it matches speed
        }

        // Overall rating
        let overall: OverallRating
        if mode == .practical && speedScore >= 3 && rpmScore == 2 {
            // Practical mode: Good speed + typical RPM = still good overall
            overall = .good
        } else {
            let overallScore = min(speedScore, rpmScore)
            switch overallScore {
            case 1: overall = .poor
            case 2: overall = .fair
            case 3: overall = .good
            default: overall = .excellent
            }
        }

        // Build summaries
        let speedSummary: String
        switch downloadMbps {
        case ..<10:
            speedSummary = "Limited bandwidth"
        case 10..<50:
            speedSummary = "Good for streaming and browsing"
        case 50..<200:
            speedSummary = "Fast for most activities"
        default:
            speedSummary = "Very fast connection"
        }

        let responsivenessSummary: String
        if let rpm = rpm {
            switch mode {
            case .practical:
                switch rpm {
                case ..<200:
                    responsivenessSummary = "May lag during heavy use"
                case 200..<400:
                    responsivenessSummary = "Good for everyday use"
                case 400..<800:
                    responsivenessSummary = "Stays responsive under load"
                default:
                    responsivenessSummary = "Excellent real-time performance"
                }
            case .ietf:
                switch rpm {
                case ..<300:
                    responsivenessSummary = "Below IETF threshold (>200ms RTT)"
                case 300..<1000:
                    responsivenessSummary = "IETF Fair (60-200ms RTT)"
                case 1000..<6000:
                    responsivenessSummary = "IETF Good (10-60ms RTT)"
                default:
                    responsivenessSummary = "IETF Excellent (<10ms RTT)"
                }
            }
        } else {
            responsivenessSummary = "Responsiveness not measured"
        }

        // Build headline
        let headline: String
        if speedScore >= 3 && rpmScore <= 1 {
            headline = "Fast speeds, but laggy under load"
        } else if speedScore <= 1 && rpmScore >= 3 {
            headline = "Responsive but limited bandwidth"
        } else {
            switch overall {
            case .poor: headline = "Connection needs improvement"
            case .fair: headline = mode == .ietf ? "Below IETF 'Good' threshold" : "Works for basic tasks"
            case .good: headline = "Good all-around connection"
            case .excellent: headline = "Excellent network quality"
            }
        }

        // Top recommendation - only for actual problems
        var recommendation: String?
        if rpmScore <= 1 {
            recommendation = "Consider enabling SQM on your router to reduce bufferbloat"
        } else if speedScore <= 1 {
            recommendation = "Your speeds may be limited by your internet plan"
        }

        return NetworkQualitySummary(
            overallRating: overall,
            headline: headline,
            speedSummary: speedSummary,
            responsivenessSummary: responsivenessSummary,
            topRecommendation: recommendation
        )
    }
}
