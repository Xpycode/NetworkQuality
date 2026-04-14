import SwiftUI

struct VPNComparisonView: View {
    @StateObject private var service = VPNComparisonService()
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue

    private var speedUnit: SpeedUnit {
        SpeedUnit(rawValue: speedUnitRaw) ?? .mbps
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // VPN Status
                vpnStatusSection

                // Test controls and progress
                controlSection

                // Results comparison
                if service.withoutVPNResult != nil || service.withVPNResult != nil {
                    resultsSection
                }

                // Assessment
                if let result = service.lastResult {
                    assessmentSection(result)
                }

                Spacer()
            }
            .padding()
        }
        .onAppear {
            service.updateVPNStatus()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("VPN Comparison")
                        .font(.title2.weight(.semibold))
                    Text("Detect if your ISP is throttling your connection")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - VPN Status

    private var vpnStatusSection: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(service.currentVPNStatus.isConnected ? Color.green : Color.gray)
                .frame(width: 12, height: 12)

            Text(service.currentVPNStatus.displayName)
                .font(.subheadline.weight(.medium))

            Spacer()

            Button {
                service.updateVPNStatus()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Control Section

    private var controlSection: some View {
        VStack(spacing: 16) {
            if service.isRunning {
                // Progress view
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)

                    Text(service.currentPhase.rawValue)
                        .font(.headline)

                    // Show live speeds during testing phases
                    if service.currentPhase == .testingWithVPN || service.currentPhase == .testingWithoutVPN {
                        if service.currentDownloadSpeed > 0 || service.currentUploadSpeed > 0 {
                            HStack(spacing: 20) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundStyle(.blue)
                                    Text(formatSpeed(service.currentDownloadSpeed))
                                        .font(.system(.body, design: .rounded, weight: .semibold))
                                        .monospacedDigit()
                                }

                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(formatSpeed(service.currentUploadSpeed))
                                        .font(.system(.body, design: .rounded, weight: .semibold))
                                        .monospacedDigit()
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    } else {
                        Text(service.progress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if service.currentPhase == .waitingForVPN {
                        Text("Toggle your VPN connection, then wait for the test to continue automatically.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Button("Cancel") {
                        service.cancel()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // Start button
                VStack(spacing: 12) {
                    Button {
                        Task {
                            await service.runComparison()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Run VPN Comparison")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("This will run two speed tests: one with VPN and one without. You'll be prompted to toggle your VPN connection between tests.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        VStack(spacing: 16) {
            Text("Comparison Results")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 20) {
                // Without VPN
                resultCard(
                    title: "Without VPN",
                    subtitle: "Direct Connection",
                    snapshot: service.withoutVPNResult,
                    icon: "globe",
                    color: .blue
                )

                // Comparison arrows
                VStack(spacing: 8) {
                    if let dlDiff = service.lastResult?.downloadDifferencePercent {
                        differenceIndicator(value: dlDiff, label: "DL")
                    }
                    if let ulDiff = service.lastResult?.uploadDifferencePercent {
                        differenceIndicator(value: ulDiff, label: "UL")
                    }
                }
                .frame(width: 60)

                // With VPN
                resultCard(
                    title: "With VPN",
                    subtitle: service.withVPNResult?.vpnStatus ?? "Pending",
                    snapshot: service.withVPNResult,
                    icon: "shield.fill",
                    color: .green
                )
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func resultCard(title: String, subtitle: String, snapshot: SpeedTestSnapshot?, icon: String, color: Color) -> some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let snapshot = snapshot {
                Divider()

                // Download
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text("Download")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(formatSpeed(snapshot.downloadMbps))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                }

                // Upload
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text("Upload")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(formatSpeed(snapshot.uploadMbps))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                }

                // Latency
                if let latency = snapshot.latencyMs {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Latency")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(String(format: "%.0f ms", latency))
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                    }
                }
            } else {
                // Pending state
                VStack {
                    Image(systemName: "hourglass")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 120)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func differenceIndicator(value: Double, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: value >= 0 ? "arrow.up" : "arrow.down")
                .font(.caption2)
                .foregroundStyle(value >= 0 ? .green : .red)

            Text(String(format: "%+.0f%%", value))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(value >= 0 ? .green : .red)

            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Assessment Section

    private func assessmentSection(_ result: VPNComparisonResult) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: result.assessment.icon)
                    .font(.title2)
                    .foregroundStyle(assessmentColor(result.assessment))

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.assessment.title)
                        .font(.headline)
                    Text(result.assessment.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Tips based on assessment
            if case .likelyThrottling = result.assessment {
                tipView(
                    icon: "lightbulb.fill",
                    title: "What you can do",
                    tips: [
                        "Use a VPN to bypass throttling for streaming or downloads",
                        "Contact your ISP if throttling violates your service agreement",
                        "Consider switching to an ISP with no throttling policy"
                    ]
                )
            }
        }
        .padding()
        .background(assessmentColor(result.assessment).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func tipView(icon: String, title: String, tips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.yellow)
                Text(title)
                    .font(.caption.weight(.medium))
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(tips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(tip)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func formatSpeed(_ mbps: Double) -> String {
        let formatted = speedUnit.format(mbps)
        return "\(formatted.value) \(formatted.unit)"
    }

    private func assessmentColor(_ assessment: ThrottlingAssessment) -> Color {
        switch assessment {
        case .likelyThrottling:
            return .orange
        case .normalOverhead:
            return .green
        case .vpnBottleneck:
            return .red
        case .inconclusive:
            return .gray
        }
    }
}

#Preview {
    VPNComparisonView()
        .frame(width: 600, height: 800)
}
