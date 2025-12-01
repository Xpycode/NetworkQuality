import SwiftUI
import Charts

struct SpeedGraphView: View {
    let speedHistory: [SpeedDataPoint]
    let averageDownload: Double
    let averageUpload: Double
    let maxDownload: Double
    let maxUpload: Double

    @State private var selectedDataPoint: SpeedDataPoint?
    @State private var showDownload: Bool = true
    @State private var showUpload: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with toggles
            HStack {
                Text("Speed History")
                    .font(.headline)

                Spacer()

                Toggle("Download", isOn: $showDownload)
                    .toggleStyle(.checkbox)
                    .foregroundStyle(.blue)

                Toggle("Upload", isOn: $showUpload)
                    .toggleStyle(.checkbox)
                    .foregroundStyle(.green)
            }

            if speedHistory.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Run multiple tests to see speed history")
                )
                .frame(height: 250)
            } else {
                // Main chart
                Chart {
                    if showDownload {
                        ForEach(speedHistory) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Download", point.downloadMbps)
                            )
                            .foregroundStyle(.blue)
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Download", point.downloadMbps)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue.opacity(0.3), .blue.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Download", point.downloadMbps)
                            )
                            .foregroundStyle(.blue)
                            .symbolSize(30)
                        }
                    }

                    if showUpload {
                        ForEach(speedHistory) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Upload", point.uploadMbps)
                            )
                            .foregroundStyle(.green)
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Upload", point.uploadMbps)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green.opacity(0.3), .green.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Upload", point.uploadMbps)
                            )
                            .foregroundStyle(.green)
                            .symbolSize(30)
                        }
                    }

                    // Average lines
                    if showDownload && averageDownload > 0 {
                        RuleMark(y: .value("Avg Download", averageDownload))
                            .foregroundStyle(.blue.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .trailing, alignment: .leading) {
                                Text("Avg")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                    }

                    if showUpload && averageUpload > 0 {
                        RuleMark(y: .value("Avg Upload", averageUpload))
                            .foregroundStyle(.green.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let mbps = value.as(Double.self) {
                                Text(formatSpeed(mbps))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .chartYAxisLabel("Speed (Mbps)", position: .leading)
                .frame(height: 250)

                // Statistics
                HStack(spacing: 20) {
                    StatCard(
                        title: "Avg Download",
                        value: formatSpeed(averageDownload),
                        color: .blue
                    )
                    StatCard(
                        title: "Max Download",
                        value: formatSpeed(maxDownload),
                        color: .blue
                    )
                    StatCard(
                        title: "Avg Upload",
                        value: formatSpeed(averageUpload),
                        color: .green
                    )
                    StatCard(
                        title: "Max Upload",
                        value: formatSpeed(maxUpload),
                        color: .green
                    )
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatSpeed(_ mbps: Double) -> String {
        if mbps >= 1000 {
            return String(format: "%.1f Gbps", mbps / 1000)
        } else if mbps >= 1 {
            return String(format: "%.1f Mbps", mbps)
        } else if mbps > 0 {
            return String(format: "%.0f Kbps", mbps * 1000)
        } else {
            return "0"
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ResponsivenessHistoryView: View {
    let results: [NetworkQualityResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Responsiveness History")
                .font(.headline)

            if results.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "speedometer",
                    description: Text("Run tests to see responsiveness history")
                )
                .frame(height: 200)
            } else {
                Chart {
                    ForEach(results) { result in
                        if let rpm = result.responsivenessValue {
                            BarMark(
                                x: .value("Time", result.timestamp),
                                y: .value("RPM", rpm)
                            )
                            .foregroundStyle(responsivenessGradient(rpm))
                            .cornerRadius(4)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let rpm = value.as(Int.self) {
                                Text("\(rpm)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .chartYAxisLabel("RPM", position: .leading)
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func responsivenessGradient(_ rpm: Int) -> Color {
        switch rpm {
        case 0..<200: return .red
        case 200..<800: return .orange
        case 800..<1500: return .yellow
        default: return .green
        }
    }
}

struct LatencyComparisonView: View {
    let result: NetworkQualityResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Latency Comparison (Averages)")
                .font(.headline)

            if let result = result {
                Chart {
                    if let idle = result.avgIdleH2ReqResp {
                        BarMark(
                            x: .value("Type", "Idle H2"),
                            y: .value("Latency", idle)
                        )
                        .foregroundStyle(.blue)
                    }

                    if let tcp = result.avgIdleTcpHandshake {
                        BarMark(
                            x: .value("Type", "TCP"),
                            y: .value("Latency", tcp)
                        )
                        .foregroundStyle(.green)
                    }

                    if let tls = result.avgIdleTlsHandshake {
                        BarMark(
                            x: .value("Type", "TLS"),
                            y: .value("Latency", tls)
                        )
                        .foregroundStyle(.orange)
                    }

                    if let loaded = result.avgLoadedH2ReqResp ?? result.avgLoadedSelfH2ReqResp {
                        BarMark(
                            x: .value("Type", "Loaded H2"),
                            y: .value("Latency", loaded)
                        )
                        .foregroundStyle(.purple)
                    }
                }
                .chartYAxisLabel("Milliseconds", position: .leading)
                .frame(height: 200)
            } else {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.bar",
                    description: Text("Run a test to see latency comparison")
                )
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    let sampleData = (0..<10).map { i in
        SpeedDataPoint(
            timestamp: Date().addingTimeInterval(Double(i) * -60),
            downloadMbps: Double.random(in: 100...500),
            uploadMbps: Double.random(in: 20...100)
        )
    }

    return SpeedGraphView(
        speedHistory: sampleData,
        averageDownload: 300,
        averageUpload: 60,
        maxDownload: 500,
        maxUpload: 100
    )
    .frame(width: 600, height: 400)
}
