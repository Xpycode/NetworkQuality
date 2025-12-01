import SwiftUI

struct SpeedGaugeView: View {
    let title: String
    let speed: Double  // Speed in Mbps (megabits per second)
    let maxSpeed: Double
    let color: Color
    let icon: String
    var speedUnit: SpeedUnit = .mbps

    private var progress: Double {
        guard maxSpeed > 0 else { return 0 }
        return min(speed / maxSpeed, 1.0)
    }

    private var formattedSpeedValue: String {
        speedUnit.format(speed).value
    }

    private var formattedSpeedUnit: String {
        speedUnit.format(speed).unit
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

                    Text(formattedSpeedValue)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.default, value: formattedSpeedValue)

                    Text(formattedSpeedUnit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 160, height: 160)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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
