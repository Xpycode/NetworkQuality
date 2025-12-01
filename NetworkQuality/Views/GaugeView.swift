import SwiftUI

struct SpeedGaugeView: View {
    let title: String
    let speed: Double
    let maxSpeed: Double
    let color: Color
    let icon: String

    private var progress: Double {
        guard maxSpeed > 0 else { return 0 }
        return min(speed / maxSpeed, 1.0)
    }

    private var formattedSpeed: String {
        if speed >= 1000 {
            return String(format: "%.2f", speed / 1000)
        } else if speed >= 1 {
            return String(format: "%.1f", speed)
        } else {
            return String(format: "%.0f", speed * 1000)
        }
    }

    private var speedUnit: String {
        if speed >= 1000 {
            return "Gbps"
        } else if speed >= 1 {
            return "Mbps"
        } else {
            return "Kbps"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Background arc
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(
                        color.opacity(0.2),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))

                // Progress arc
                Circle()
                    .trim(from: 0.15, to: 0.15 + (0.7 * progress))
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.5), color],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .animation(.easeOut(duration: 0.5), value: progress)

                // Center content
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.title)
                        .foregroundStyle(color)

                    Text(formattedSpeed)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.default, value: formattedSpeed)

                    Text(speedUnit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, height: 180)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

struct ResponsivenessGaugeView: View {
    let rpm: Int?
    let maxRpm: Int = 2000

    private var progress: Double {
        guard let rpm = rpm else { return 0 }
        return min(Double(rpm) / Double(maxRpm), 1.0)
    }

    private var rating: String {
        guard let rpm = rpm else { return "N/A" }
        switch rpm {
        case 0..<200: return "Low"
        case 200..<800: return "Medium"
        case 800..<1500: return "High"
        default: return "Excellent"
        }
    }

    private var ratingColor: Color {
        guard let rpm = rpm else { return .gray }
        switch rpm {
        case 0..<200: return .red
        case 200..<800: return .orange
        case 800..<1500: return .yellow
        default: return .green
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 30)

                // Progress bar
                GeometryReader { geometry in
                    HStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [.red, .orange, .yellow, .green],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progress)
                            .animation(.easeOut(duration: 0.5), value: progress)
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Image(systemName: "speedometer")
                    .foregroundStyle(ratingColor)

                if let rpm = rpm {
                    Text("\(rpm) RPM")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                } else {
                    Text("N/A")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                Text("(\(rating))")
                    .font(.subheadline)
                    .foregroundStyle(ratingColor)
            }

            Text("Responsiveness")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct LatencyGaugeView: View {
    let latency: Double?
    let maxLatency: Double = 200

    private var progress: Double {
        guard let latency = latency else { return 0 }
        return min(latency / maxLatency, 1.0)
    }

    private var rating: String {
        guard let latency = latency else { return "N/A" }
        switch latency {
        case 0..<20: return "Excellent"
        case 20..<50: return "Good"
        case 50..<100: return "Fair"
        default: return "Poor"
        }
    }

    private var ratingColor: Color {
        guard let latency = latency else { return .gray }
        switch latency {
        case 0..<20: return .green
        case 20..<50: return .yellow
        case 50..<100: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                if let latency = latency {
                    Text(String(format: "%.1f", latency))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("ms")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("N/A")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }

            Text(rating)
                .font(.caption)
                .foregroundStyle(ratingColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(ratingColor.opacity(0.2))
                .clipShape(Capsule())

            Text("Base Latency")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("Speed Gauge") {
    HStack {
        SpeedGaugeView(
            title: "Download",
            speed: 450.5,
            maxSpeed: 1000,
            color: .blue,
            icon: "arrow.down.circle.fill"
        )
        SpeedGaugeView(
            title: "Upload",
            speed: 85.2,
            maxSpeed: 1000,
            color: .green,
            icon: "arrow.up.circle.fill"
        )
    }
    .padding()
}

#Preview("Responsiveness") {
    ResponsivenessGaugeView(rpm: 850)
        .frame(width: 300)
}

#Preview("Latency") {
    LatencyGaugeView(latency: 25.5)
        .frame(width: 150)
}
