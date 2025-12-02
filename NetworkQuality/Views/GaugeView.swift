import SwiftUI

struct SpeedGaugeView: View {
    let title: String
    let speed: Double  // Speed in Mbps (megabits per second)
    let maxSpeed: Double
    let color: Color
    let icon: String
    var speedUnit: SpeedUnit = .mbps
    var showTitle: Bool = true
    var size: CGFloat = 160

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

    private var lineWidth: CGFloat {
        size * 0.125 // Proportional line width
    }

    private var iconFont: Font {
        size < 140 ? .title3 : .title
    }

    private var speedFont: CGFloat {
        size < 140 ? 28 : 36
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background arc
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(
                        color.opacity(0.2),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
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
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .animation(.easeOut(duration: 0.5), value: progress)

                // Center content
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(iconFont)
                        .foregroundStyle(color)

                    Text(formattedSpeedValue)
                        .font(.system(size: speedFont, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.default, value: formattedSpeedValue)

                    Text(formattedSpeedUnit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)

            if showTitle {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
