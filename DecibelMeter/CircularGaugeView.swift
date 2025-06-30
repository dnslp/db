import SwiftUI

// MARK: - Data Structures for Contextual Text

enum SoundCategory: String, CaseIterable, Identifiable {
    case home = "Home"
    case work = "Work"
    case recreation = "Recreation"

    var id: String { self.rawValue }
}

struct SoundLevelData {
    let levelRange: ClosedRange<Int>
    let description: String
    let category: SoundCategory
}

let soundLevelReferenceData: [SoundLevelData] = [
    // Home
    SoundLevelData(levelRange: 50...50, description: "Refrigerator", category: .home),
    SoundLevelData(levelRange: 50...60, description: "Electric Toothbrush", category: .home),
    SoundLevelData(levelRange: 50...75, description: "Washing Machine", category: .home),
    SoundLevelData(levelRange: 50...75, description: "Air Conditioner", category: .home),
    SoundLevelData(levelRange: 50...80, description: "Electric Shaver", category: .home),
    SoundLevelData(levelRange: 55...55, description: "Coffee Percolator", category: .home),
    SoundLevelData(levelRange: 55...70, description: "Dishwasher", category: .home),
    SoundLevelData(levelRange: 60...60, description: "Sewing Machine", category: .home),
    SoundLevelData(levelRange: 60...85, description: "Vacuum Cleaner", category: .home),
    SoundLevelData(levelRange: 60...95, description: "Hair Dryer", category: .home),
    SoundLevelData(levelRange: 65...80, description: "Alarm Clock", category: .home),
    SoundLevelData(levelRange: 70...70, description: "TV Audio", category: .home),
    SoundLevelData(levelRange: 70...80, description: "Coffee Grinder", category: .home),
    SoundLevelData(levelRange: 70...95, description: "Garbage Disposal", category: .home),
    SoundLevelData(levelRange: 75...85, description: "Flush Toilet", category: .home),
    SoundLevelData(levelRange: 80...80, description: "Pop-Up Toaster", category: .home),
    SoundLevelData(levelRange: 80...80, description: "Doorbell", category: .home),
    SoundLevelData(levelRange: 80...80, description: "Ringing Telephone", category: .home),
    SoundLevelData(levelRange: 80...80, description: "Whistling Kettle", category: .home),
    SoundLevelData(levelRange: 80...90, description: "Food Mixer or Processor", category: .home),
    SoundLevelData(levelRange: 80...90, description: "Blender", category: .home),
    SoundLevelData(levelRange: 110...110, description: "Baby Crying", category: .home),
    SoundLevelData(levelRange: 110...110, description: "Squeaky Toy Held Close to Ear", category: .home),
    SoundLevelData(levelRange: 135...135, description: "Noisy Squeeze Toys", category: .home),

    // Work
    SoundLevelData(levelRange: 40...40, description: "Quiet Office, Library", category: .work),
    SoundLevelData(levelRange: 50...50, description: "Large Office", category: .work),
    SoundLevelData(levelRange: 65...95, description: "Power Lawn Mower", category: .work),
    SoundLevelData(levelRange: 80...80, description: "Manual Machine, Tools", category: .work),
    SoundLevelData(levelRange: 85...85, description: "Handsaw", category: .work),
    SoundLevelData(levelRange: 90...90, description: "Tractor", category: .work),
    SoundLevelData(levelRange: 90...115, description: "Subway", category: .work),
    SoundLevelData(levelRange: 95...95, description: "Electric drill", category: .work),
    SoundLevelData(levelRange: 100...100, description: "Factory Machinery", category: .work),
    SoundLevelData(levelRange: 100...100, description: "Woodworking Class", category: .work),
    SoundLevelData(levelRange: 105...105, description: "Snow Blower", category: .work),
    SoundLevelData(levelRange: 110...110, description: "Power Saw", category: .work),
    SoundLevelData(levelRange: 110...110, description: "Leaf Blower", category: .work),
    SoundLevelData(levelRange: 120...125, description: "Chainsaw, Hammer On Nail", category: .work),
    SoundLevelData(levelRange: 120...120, description: "Pneumatic Drills, Heavy Machine", category: .work),
    SoundLevelData(levelRange: 120...120, description: "Jet Plane at Ramp", category: .work),
    SoundLevelData(levelRange: 120...120, description: "Ambulance Siren", category: .work),
    SoundLevelData(levelRange: 130...130, description: "Jackhammer, Power Drill", category: .work),
    SoundLevelData(levelRange: 130...130, description: "Air Raid", category: .work),
    SoundLevelData(levelRange: 130...130, description: "Percussion Section at Symphony", category: .work), // Also recreation, but often a work environment for musicians
    SoundLevelData(levelRange: 140...140, description: "Airplane Taking Off", category: .work),
    SoundLevelData(levelRange: 150...150, description: "Jet Engine Taking Off", category: .work),
    SoundLevelData(levelRange: 150...150, description: "Artillery Fire at 500 Feet", category: .work),
    SoundLevelData(levelRange: 189...189, description: "Rocket Launching from Pad", category: .work),

    // Recreation
    SoundLevelData(levelRange: 40...40, description: "Quiet Residential Area", category: .recreation),
    SoundLevelData(levelRange: 70...70, description: "Freeway Traffic", category: .recreation),
    SoundLevelData(levelRange: 85...85, description: "Heavy Traffic, Noisy Restaurant", category: .recreation),
    SoundLevelData(levelRange: 90...90, description: "Truck, Shouted Conversation", category: .recreation),
    SoundLevelData(levelRange: 95...110, description: "Motorcycle", category: .recreation),
    SoundLevelData(levelRange: 100...100, description: "Snowmobile", category: .recreation),
    SoundLevelData(levelRange: 100...100, description: "School Dance, Boom Box", category: .recreation),
    SoundLevelData(levelRange: 110...110, description: "Music Club, Disco", category: .recreation),
    SoundLevelData(levelRange: 110...110, description: "Busy Video Arcade", category: .recreation),
    SoundLevelData(levelRange: 110...110, description: "Symphony Concert", category: .recreation),
    SoundLevelData(levelRange: 110...110, description: "Car Horn", category: .recreation),
    SoundLevelData(levelRange: 110...120, description: "Rock Concert", category: .recreation),
    SoundLevelData(levelRange: 112...112, description: "Personal Music Player on High", category: .recreation),
    SoundLevelData(levelRange: 117...117, description: "Football Game Stadium", category: .recreation),
    SoundLevelData(levelRange: 120...120, description: "Band Concert", category: .recreation),
    SoundLevelData(levelRange: 125...125, description: "Auto Stereo", category: .recreation),
    SoundLevelData(levelRange: 130...130, description: "Stock Car Races", category: .recreation),
    SoundLevelData(levelRange: 143...143, description: "Bicycle Horn", category: .recreation),
    SoundLevelData(levelRange: 150...150, description: "Firecracker", category: .recreation),
    SoundLevelData(levelRange: 156...156, description: "Cap Gun", category: .recreation),
    SoundLevelData(levelRange: 157...157, description: "Balloon Pop", category: .recreation),
    SoundLevelData(levelRange: 162...162, description: "Fireworks (at 3 Feet)", category: .recreation),
    SoundLevelData(levelRange: 163...163, description: "Rifle", category: .recreation),
    SoundLevelData(levelRange: 166...170, description: "Handgun, Shotgun", category: .recreation)
]

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
    var selectedCategory: SoundCategory = .home // Default category

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

    func getContextualText(for level: Float, category: SoundCategory) -> String { // Changed to internal
        let currentLevel = Int(level)

        let matchingItems = soundLevelReferenceData.filter { item in
            item.category == category && item.levelRange.contains(currentLevel)
        }

        if matchingItems.isEmpty {
            if currentLevel < 40 {
                return "Quiet Environment"
            } else if currentLevel > 140 { // Example upper threshold
                return "Very Loud"
            }
            // Try to find items in other categories if none in selected, or provide a generic sound level description
            let anyCategoryItems = soundLevelReferenceData.filter { item in
                item.levelRange.contains(currentLevel)
            }
            if !anyCategoryItems.isEmpty {
                return anyCategoryItems.map { $0.description }.prefix(2).joined(separator: " / ") + (anyCategoryItems.count > 2 ? "..." : "")
            }
            return "Moderate Noise Level" // Fallback if no items match at all
        }

        // Join descriptions, limiting to a reasonable number to avoid overflow
        let descriptions = matchingItems.map { $0.description }
        if descriptions.count > 3 {
            return descriptions.prefix(3).joined(separator: " / ") + "..."
        } else {
            return descriptions.joined(separator: " / ")
        }
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
                let normalizedLevel = CGFloat(min(level / 140, 1))

                // Single Progress Arc
                Circle()
                    // The trim needs to correspond to the visual representation.
                    // If 0 degrees is at the right, and we rotate by 180 degrees, 0 is now at the left.
                    // We want the gauge to start at visual bottom-left.
                    // This corresponds to -135 degrees or 225 degrees in a standard Cartesian coordinate system (0 right, 90 up).
                    // SwiftUI's Circle path starts at the right (0 degrees) and goes clockwise.
                    // A rotation of .degrees(135) would make the circle's 0-degree point align with bottom-left.
                    // Then trim from 0 to normalizedLevel * (270/360) if we want a 270 degree sweep.
                    .trim(from: 0, to: normalizedLevel * 0.75) // Assuming gauge spans 3/4 of a circle (270 degrees)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: currentProgressArcColors),
                            center: .center,
                            // Gradient should start where the arc starts.
                            // If arc starts at -135 deg (bottom-left) and sweeps 270 deg, it ends at 135 deg (top-right).
                            startAngle: .degrees(0), // Start of the gradient relative to the shape's own coord system
                            endAngle: .degrees(360 * 0.75)   // End of gradient sweep, matching the arc's max sweep
                        ),
                        style: currentStrokeStyle
                    )
                    // Rotate the entire circle so that its 0-degree mark (start of the trim)
                    // is positioned at the visual bottom-left of the gauge.
                    // Bottom-left is at an angle of 225 degrees (or -135 degrees).
                    // SwiftUI circle's 0 is right. To move this to bottom-left (225 deg), rotate by 225 deg.
                    // Or, to make it more like Apple's, which often starts at ~7 o'clock and goes to ~5 o'clock.
                    // Let's try starting at -135 degrees (225) for the path.
                    .rotationEffect(.degrees(135)) // Rotates the circle so 0 point of trim is at bottom-left

                VStack {
                    Text("\(Int(level)) dB")
                        .font(.system(size: size * 0.2, weight: .bold, design: fontDesign ?? .rounded)) // Use new property
                        .foregroundColor(textColor) // Use new property (nil means default)
                    Text(getContextualText(for: level, category: selectedCategory))
                        .font(.system(size: size * 0.05, weight: .medium, design: fontDesign ?? .rounded))
                        .foregroundColor(textColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(height: size * 0.15, alignment: .top) // Fixed height for contextual text
                        .padding(.top, size * 0.02)
                }
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
