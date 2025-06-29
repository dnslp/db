import SwiftUI

/// A custom shadow style configuration.
struct ShadowStyle {
    var color: Color = .black.opacity(0.2)
    var radius: CGFloat = 5
    var x: CGFloat = 0
    var y: CGFloat = 2
}

/// A simple circular gauge that scales with its container, with customizable "Liquid Glass" styling options.
struct CircularGaugeView: View {
    /// Current level between 0 and 140 dB.
    var level: Float

    // Styling Properties for Liquid Glass effect
    var gaugeBackgroundColor: Color? = nil
    var gaugeBackgroundMaterial: Material? = nil
    var progressArcColors: [Color]? = nil
    var progressArcStrokeStyle: StrokeStyle? = nil
    var showShadow: Bool = false
    var customShadow: ShadowStyle? = nil
    var textColor: Color? = nil
    var fontDesign: Font.Design? = .rounded

    // Defined color key points for default dynamic gradient
    private let defaultColorKeyPoints: [(level: Float, h: Double, s: Double, b: Double)] = [
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

    // Calculates color based on defaultColorKeyPoints
    private func getDefaultColor(for level: Float) -> Color {
        guard !defaultColorKeyPoints.isEmpty else {
            return .gray // Should not happen if defaultColorKeyPoints is initialized
        }

        // Handle cases where level is outside the defined range
        if level <= defaultColorKeyPoints.first!.level {
            let first = defaultColorKeyPoints.first!
            return Color(hue: first.h, saturation: first.s, brightness: first.b)
        }
        if level >= defaultColorKeyPoints.last!.level {
            let last = defaultColorKeyPoints.last!
            return Color(hue: last.h, saturation: last.s, brightness: last.b)
        }

        // Find the two key points that bracket the current level and interpolate
        for i in 0..<(defaultColorKeyPoints.count - 1) {
            let p1 = defaultColorKeyPoints[i]
            let p2 = defaultColorKeyPoints[i+1]
            if level >= p1.level && level < p2.level { // Use < for p2.level to avoid issues if level equals p2.level
                return interpolateColor(level: level, p1: p1, p2: p2)
            }
        }

        // Fallback to the last color if no segment is found (should ideally be covered by the checks above)
        let last = defaultColorKeyPoints.last!
        return Color(hue: last.h, saturation: last.s, brightness: last.b)
    }

    // Determines the colors for the progress arc gradient.
    // Uses `progressArcColors` if provided, otherwise generates dynamic colors.
    private var currentProgressArcColors: [Color] {
        if let customColors = progressArcColors, !customColors.isEmpty {
            return customColors
        } else {
            let currentLevel = max(0, min(level, 140)) // Clamp level to 0-140
            // Determine colors for the gradient spread
            // The spread (-20, +20) determines how wide the color transition in the angular gradient will be.
            let color1 = getDefaultColor(for: max(0, currentLevel - 20)) // Cooler end
            let color2 = getDefaultColor(for: currentLevel)              // Center color
            let color3 = getDefaultColor(for: min(140, currentLevel + 20)) // Warmer end
            return [color1, color2, color3]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size.width * 0.75
            let defaultLineWidth = size * 0.05
            let currentStrokeStyle = progressArcStrokeStyle ?? StrokeStyle(lineWidth: defaultLineWidth, lineCap: .round)

            ZStack {
                // Background
                if let material = gaugeBackgroundMaterial {
                    Circle()
                        .fill(material)
                } else {
                    Circle()
                        .fill(gaugeBackgroundColor ?? Color.secondary.opacity(0.1)) // Default to a more translucent Liquid Glass background
                }
                // Stroke for the background circle if no material is used or if a stroke is desired over material
                Circle()
                    .stroke(gaugeBackgroundColor ?? Color.secondary.opacity(0.2), lineWidth: currentStrokeStyle.lineWidth * 0.5) // Thinner stroke for background outline


                // Progress arc
                Circle()
                    .trim(from: 0, to: CGFloat(min(level / 140, 1)))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: currentProgressArcColors), // Use new property
                            center: .center
                        ),
                        style: currentStrokeStyle // Use new property
                    )
                    .rotationEffect(.degrees(-90))

                Text("\(Int(level)) dB")
                    .font(.system(size: size * 0.2, weight: .bold, design: fontDesign ?? .rounded)) // Use new property
                    .foregroundColor(textColor) // Use new property (nil means default)
            }
            .frame(width: size, height: size)
            .shadow(
                color: customShadow?.color ?? (showShadow ? Color.black.opacity(0.2) : Color.clear),
                radius: customShadow?.radius ?? (showShadow ? 5 : 0),
                x: customShadow?.x ?? (showShadow ? 0 : 0),
                y: customShadow?.y ?? (showShadow ? 2 : 0)
            )
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

#Preview("Default Style") {
    CircularGaugeView(level: 70)
        .frame(width: 300, height: 300)
        .padding()
}

#Preview("Liquid Glass Style") {
    CircularGaugeView(
        level: 85,
        gaugeBackgroundMaterial: .ultraThinMaterial,
        progressArcColors: [Color.blue.opacity(0.5), Color.purple.opacity(0.8), Color.pink.opacity(0.6)],
        progressArcStrokeStyle: StrokeStyle(lineWidth: 15, lineCap: .butt),
        showShadow: true,
        textColor: .primary.opacity(0.8),
        fontDesign: .default
    )
    .frame(width: 300, height: 300)
    .background(Color.gray.opacity(0.2)) // So material effect is visible
    .padding()
}

#Preview("Custom Colors & Shadow") {
    CircularGaugeView(
        level: 50,
        gaugeBackgroundColor: Color.black.opacity(0.7),
        progressArcColors: [Color.green, Color.yellow, Color.orange],
        customShadow: ShadowStyle(color: .blue.opacity(0.5), radius: 10, x: 5, y: 5),
        textColor: .white
    )
    .frame(width: 200, height: 200)
    .padding()
}
