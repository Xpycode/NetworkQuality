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
