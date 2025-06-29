import SwiftUI

/// A simple circular gauge that scales with its container.
struct CircularGaugeView: View {
    /// Current level between 0 and 140 dB.
    var level: Float

    // Defined color key points for dynamic gradient
    private let colorKeyPoints: [(level: Float, h: Double, s: Double, b: Double)] = [
        (0,   0.58, 0.6, 0.95), // Light Sky Blue
        (30,  0.50, 0.7, 0.9),  // Sky Blue
        (50,  0.33, 0.75, 0.85), // Safe Green
        (70,  0.20, 0.85, 0.9), // Light Yellow-Green
        (85,  0.15, 0.9, 0.9),  // Yellow-Orange
        (100, 0.08, 0.9, 0.85), // Orange-Red
        (120, 0.02, 0.95, 0.8), // Red
        (140, 0.0,  1.0, 0.7)   // Dark Saturated Red
    ]

    // Helper function to interpolate HSB color components
    private func interpolateColor(level: Float, p1: (level: Float, h: Double, s: Double, b: Double), p2: (level: Float, h: Double, s: Double, b: Double)) -> Color {
        // Ensure p2.level is greater than p1.level to prevent division by zero or negative t
        guard p2.level > p1.level else { return Color(hue: p1.h, saturation: p1.s, brightness: p1.b) }

        let t = (level - p1.level) / (p2.level - p1.level)

        // Handle hue interpolation carefully if it needs to wrap around the color wheel (not critical for this specific spectrum)
        let h = p1.h + Double(t) * (p2.h - p1.h)
        let s = p1.s + Double(t) * (p2.s - p1.s)
        let b = p1.b + Double(t) * (p2.b - p1.b)

        return Color(hue: h, saturation: s, brightness: b)
    }

    private func getColor(for level: Float) -> Color {
        guard !colorKeyPoints.isEmpty else {
            return .gray // Should not happen if colorKeyPoints is initialized
        }

        // Handle cases where level is outside the defined range
        if level <= colorKeyPoints.first!.level {
            let first = colorKeyPoints.first!
            return Color(hue: first.h, saturation: first.s, brightness: first.b)
        }
        if level >= colorKeyPoints.last!.level {
            let last = colorKeyPoints.last!
            return Color(hue: last.h, saturation: last.s, brightness: last.b)
        }

        // Find the two key points that bracket the current level and interpolate
        for i in 0..<(colorKeyPoints.count - 1) {
            let p1 = colorKeyPoints[i]
            let p2 = colorKeyPoints[i+1]
            if level >= p1.level && level < p2.level { // Use < for p2.level to avoid issues if level equals p2.level
                return interpolateColor(level: level, p1: p1, p2: p2)
            }
        }

        // Fallback to the last color if no segment is found (should ideally be covered by the checks above)
        let last = colorKeyPoints.last!
        return Color(hue: last.h, saturation: last.s, brightness: last.b)
    }

    private var dynamicGradientColors: [Color] {
        let currentLevel = max(0, min(level, 140)) // Clamp level to 0-140

        // Determine colors for the gradient spread
        // The spread (-15, +15) determines how wide the color transition in the angular gradient will be.
        let color1 = getColor(for: max(0, currentLevel - 20)) // Cooler end, wider spread
        let color2 = getColor(for: currentLevel)              // Center color for current level
        let color3 = getColor(for: min(140, currentLevel + 20)) // Warmer end, wider spread

        return [color1, color2, color3]
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size.width * 0.75
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: size * 0.05)

                // Progress arc
                Circle()
                    .trim(from: 0, to: CGFloat(min(level / 140, 1)))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: dynamicGradientColors), // Use dynamic colors
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text("\(Int(level)) dB")
                    .font(.system(size: size * 0.2, weight: .bold, design: .rounded))
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

#Preview {
    CircularGaugeView(level: 70)
        .frame(width: 300, height: 300)
        .padding()
}
