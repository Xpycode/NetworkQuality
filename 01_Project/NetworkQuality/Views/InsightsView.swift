import SwiftUI

/// Displays plain-language insights about network quality
struct InsightsView: View {
    let result: NetworkQualityResult
    @AppStorage("rpmRatingMode") private var rpmRatingModeRaw = RPMRatingMode.practical.rawValue

    private var rpmRatingMode: RPMRatingMode {
        RPMRatingMode(rawValue: rpmRatingModeRaw) ?? .practical
    }

    private var speedInsight: NetworkInsights.SpeedInsight {
        NetworkInsights.speedInsight(
            downloadMbps: result.downloadSpeedMbps,
            uploadMbps: result.uploadSpeedMbps
        )
    }

    private var responsivenessInsight: NetworkInsights.ResponsivenessInsight? {
        guard let rpm = result.responsivenessValue else { return nil }
        return NetworkInsights.responsivenessInsight(rpm: rpm, mode: rpmRatingMode)
    }

    private var overallSummary: NetworkInsights.NetworkQualitySummary {
        NetworkInsights.overallSummary(
            downloadMbps: result.downloadSpeedMbps,
            uploadMbps: result.uploadSpeedMbps,
            rpm: result.responsivenessValue,
            mode: rpmRatingMode
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Overall Summary Card
            OverallSummaryCard(summary: overallSummary)

            // Bufferbloat Visualization (if we have both idle and loaded latency)
            if let idleLatency = result.baseRtt, let rpm = result.responsivenessValue {
                BufferbloatVisualization(idleLatencyMs: idleLatency, rpm: rpm)
            }

            // What Can You Do Section
            WhatCanYouDoSection(speedInsight: speedInsight)

            // Responsiveness Detail (if available)
            if let rpmInsight = responsivenessInsight {
                ResponsivenessDetailSection(insight: rpmInsight)
            }
        }
    }
}

// MARK: - Overall Summary Card

struct OverallSummaryCard: View {
    let summary: NetworkInsights.NetworkQualitySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: ratingIcon)
                    .font(.title)
                    .foregroundStyle(summary.overallRating.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.overallRating.label)
                        .font(.headline)
                        .foregroundStyle(summary.overallRating.color)
                    Text(summary.headline)
                        .font(.title3.weight(.medium))
                }

                Spacer()
            }

            Divider()

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Speed", systemImage: "speedometer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary.speedSummary)
                        .font(.subheadline)
                }

                Divider()
                    .frame(height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Label("Responsiveness", systemImage: "waveform.path.ecg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary.responsivenessSummary)
                        .font(.subheadline)
                }
            }

            if let recommendation = summary.topRecommendation {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    Text(recommendation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(summary.overallRating.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var ratingIcon: String {
        switch summary.overallRating {
        case .poor: return "exclamationmark.triangle.fill"
        case .fair: return "minus.circle.fill"
        case .good: return "checkmark.circle.fill"
        case .excellent: return "star.circle.fill"
        }
    }
}

// MARK: - What Can You Do Section

struct WhatCanYouDoSection: View {
    let speedInsight: NetworkInsights.SpeedInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What can you do with this connection?")
                .font(.headline)

            Text(speedInsight.headline)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                ForEach(speedInsight.capabilities, id: \.activity) { capability in
                    CapabilityRow(capability: capability)
                }
            }

            if !speedInsight.limitations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(speedInsight.limitations, id: \.self) { limitation in
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text(limitation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct CapabilityRow: View {
    let capability: NetworkInsights.ActivityCapability

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: capability.icon)
                .font(.body)
                .foregroundStyle(capability.supported ? .green : .red)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(capability.activity)
                    .font(.subheadline.weight(.medium))
                Text(capability.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: capability.supported ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(capability.supported ? .green : .red)
                .font(.caption)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Responsiveness Detail Section

struct ResponsivenessDetailSection: View {
    let insight: NetworkInsights.ResponsivenessInsight
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: insight.rating.icon)
                    .foregroundStyle(insight.rating.color)
                Text("Network Responsiveness")
                    .font(.headline)
                Spacer()
                Text(insight.rating.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(insight.rating.color)
            }

            Text(insight.headline)
                .font(.subheadline.weight(.medium))

            Text(insight.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)

            // Activity status grid
            VStack(alignment: .leading, spacing: 8) {
                Text("Real-time activity performance:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(insight.activities) { activity in
                        ActivityStatusRow(activity: activity)
                    }
                }
            }

            // Recommendation
            if let recommendation = insight.recommendation {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(.blue)
                    Text(recommendation)
                        .font(.callout)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(insight.rating.color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ActivityStatusRow: View {
    let activity: NetworkInsights.ActivityStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: activity.status.icon)
                .foregroundStyle(activity.status.color)
                .font(.caption)

            Text(activity.name)
                .font(.caption.weight(.medium))

            Spacer()

            Text(activity.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Bufferbloat Visualization

struct BufferbloatVisualization: View {
    let idleLatencyMs: Double
    let rpm: Int

    // Loaded latency calculated from RPM: 60000ms / RPM = RTT in ms
    private var loadedLatencyMs: Double {
        60000.0 / Double(rpm)
    }

    private var bufferbloatMs: Double {
        max(0, loadedLatencyMs - idleLatencyMs)
    }

    private var bufferbloatMultiplier: Double {
        guard idleLatencyMs > 0 else { return 1 }
        return loadedLatencyMs / idleLatencyMs
    }

    private var severity: BufferbloatSeverity {
        switch bufferbloatMultiplier {
        case ..<1.5: return .minimal
        case 1.5..<3: return .moderate
        case 3..<6: return .significant
        default: return .severe
        }
    }

    enum BufferbloatSeverity {
        case minimal, moderate, significant, severe

        var color: Color {
            switch self {
            case .minimal: return .green
            case .moderate: return .blue
            case .significant: return .orange
            case .severe: return .red
            }
        }

        var label: String {
            switch self {
            case .minimal: return "Minimal"
            case .moderate: return "Moderate"
            case .significant: return "Significant"
            case .severe: return "Severe"
            }
        }

        var explanation: String {
            switch self {
            case .minimal:
                return "Your network maintains low latency even under load. Real-time applications work great."
            case .moderate:
                return "Some latency increase under load, but generally acceptable for most uses."
            case .significant:
                return "Noticeable delay when network is busy. Video calls may stutter during large downloads."
            case .severe:
                return "High latency under load causes poor experience for real-time apps. Consider enabling SQM on your router."
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(severity.color)
                Text("Bufferbloat")
                    .font(.headline)
                Spacer()
                Text(severity.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(severity.color)
            }

            // Bar chart visualization
            VStack(alignment: .leading, spacing: 8) {
                // Idle latency bar
                LatencyBar(
                    label: "Idle",
                    value: idleLatencyMs,
                    maxValue: max(loadedLatencyMs, idleLatencyMs),
                    color: .green,
                    description: "When network is quiet"
                )

                // Loaded latency bar
                LatencyBar(
                    label: "Loaded",
                    value: loadedLatencyMs,
                    maxValue: max(loadedLatencyMs, idleLatencyMs),
                    color: severity.color,
                    description: "When network is busy"
                )
            }

            // Bufferbloat amount
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Latency increase under load")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("+\(Int(bufferbloatMs)) ms")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(severity.color)
                        Text("(\(String(format: "%.1f", bufferbloatMultiplier))× slower)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            // Explanation
            Text(severity.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)

            // What is bufferbloat? expandable
            ExpandableSection(title: "What is bufferbloat?") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bufferbloat occurs when your router or modem queues too many packets, causing delays. It's why you can have fast download speeds but still experience:")
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Video call freezes during downloads", systemImage: "video.slash")
                        Label("Game lag spikes when others are streaming", systemImage: "gamecontroller")
                        Label("Sluggish web browsing on a \"fast\" connection", systemImage: "globe")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text("**Solution:** Enable SQM (Smart Queue Management) on your router, or use a router with good queue management like eero or OpenWrt.")
                        .font(.caption)
                        .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(severity.color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct LatencyBar: View {
    let label: String
    let value: Double
    let maxValue: Double
    let color: Color
    let description: String

    private var barWidth: CGFloat {
        guard maxValue > 0 else { return 0 }
        return CGFloat(value / maxValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                    .frame(width: 50, alignment: .leading)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: 20)

                        // Value bar
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.7))
                            .frame(width: geometry.size.width * barWidth, height: 20)

                        // Value label inside bar
                        Text("\(Int(value)) ms")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.leading, 8)
                    }
                }
                .frame(height: 20)
            }

            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 50)
        }
    }
}

// MARK: - Compact Insight Summary (for SpeedTestView)

struct CompactInsightSummary: View {
    let result: NetworkQualityResult
    @AppStorage("rpmRatingMode") private var rpmRatingModeRaw = RPMRatingMode.practical.rawValue

    private var rpmRatingMode: RPMRatingMode {
        RPMRatingMode(rawValue: rpmRatingModeRaw) ?? .practical
    }

    private var summary: NetworkInsights.NetworkQualitySummary {
        NetworkInsights.overallSummary(
            downloadMbps: result.downloadSpeedMbps,
            uploadMbps: result.uploadSpeedMbps,
            rpm: result.responsivenessValue,
            mode: rpmRatingMode
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ratingIcon)
                .font(.title2)
                .foregroundStyle(summary.overallRating.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.headline)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if let rpm = result.responsivenessValue {
                    let rpmInsight = NetworkInsights.responsivenessInsight(rpm: rpm, mode: rpmRatingMode)
                    Text(rpmInsight.headline)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(summary.overallRating.label)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(summary.overallRating.color.opacity(0.15))
                .foregroundStyle(summary.overallRating.color)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(summary.overallRating.color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var ratingIcon: String {
        switch summary.overallRating {
        case .poor: return "exclamationmark.triangle.fill"
        case .fair: return "minus.circle.fill"
        case .good: return "checkmark.circle.fill"
        case .excellent: return "star.circle.fill"
        }
    }
}

// MARK: - Expandable Section (fully clickable header)

struct ExpandableSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.caption.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - Previews

#Preview("Insights View - Good") {
    ScrollView {
        InsightsView(result: NetworkQualityResult(
            downloadMbps: 150,
            uploadMbps: 20,
            responsivenessRPM: 850,
            idleLatencyMs: 15,
            interfaceName: nil
        ))
        .padding()
    }
    .frame(width: 500, height: 700)
}

#Preview("Insights View - Poor RPM") {
    ScrollView {
        InsightsView(result: NetworkQualityResult(
            downloadMbps: 500,
            uploadMbps: 50,
            responsivenessRPM: 150,
            idleLatencyMs: 25,
            interfaceName: nil
        ))
        .padding()
    }
    .frame(width: 500, height: 700)
}

#Preview("Compact Summary") {
    VStack(spacing: 20) {
        CompactInsightSummary(result: NetworkQualityResult(
            downloadMbps: 150,
            uploadMbps: 20,
            responsivenessRPM: 850,
            idleLatencyMs: 15,
            interfaceName: nil
        ))

        CompactInsightSummary(result: NetworkQualityResult(
            downloadMbps: 500,
            uploadMbps: 50,
            responsivenessRPM: 150,
            idleLatencyMs: 25,
            interfaceName: nil
        ))
    }
    .padding()
    .frame(width: 400)
}
