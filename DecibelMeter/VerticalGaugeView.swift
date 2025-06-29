import SwiftUI

struct VerticalGaugeView: View {
    var level: Float
    var styleConfig: GaugeStyleConfiguration

    // Color interpolation logic (adapted from CircularGaugeView)
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

    private func interpolateColor(level: Float, p1: (level: Float, h: Double, s: Double, b: Double), p2: (level: Float, h: Double, s: Double, b: Double)) -> Color {
        guard p2.level > p1.level else { return Color(hue: p1.h, saturation: p1.s, brightness: p1.b) }
        let t = (level - p1.level) / (p2.level - p1.level)
        let h = p1.h + Double(t) * (p2.h - p1.h)
        let s = p1.s + Double(t) * (p2.s - p1.s)
        let b = p1.b + Double(t) * (p2.b - p1.b)
        return Color(hue: h, saturation: s, brightness: b)
    }

    private func getDefaultColor(for level: Float) -> Color {
        guard !defaultColorKeyPoints.isEmpty else { return .gray }
        if level <= defaultColorKeyPoints.first!.level {
            let first = defaultColorKeyPoints.first!
            return Color(hue: first.h, saturation: first.s, brightness: first.b)
        }
        if level >= defaultColorKeyPoints.last!.level {
            let last = defaultColorKeyPoints.last!
            return Color(hue: last.h, saturation: last.s, brightness: last.b)
        }
        for i in 0..<(defaultColorKeyPoints.count - 1) {
            let p1 = defaultColorKeyPoints[i]
            let p2 = defaultColorKeyPoints[i+1]
            if level >= p1.level && level < p2.level {
                return interpolateColor(level: level, p1: p1, p2: p2)
            }
        }
        let last = defaultColorKeyPoints.last!
        return Color(hue: last.h, saturation: last.s, brightness: last.b)
    }

    // Adapted for vertical gradient
    private var currentProgressGradientColors: [Color] {
        if let customColors = styleConfig.progressArcColors, !customColors.isEmpty {
            // If custom colors are defined, use them directly for the gradient stops
            // For a vertical bar, we might just want two stops, or use them as is if it looks good.
            // Let's assume they are provided in a way that makes sense for a linear gradient.
            return customColors
        } else {
            let currentLevel = max(0, min(level, 140))
            // For a vertical bar, we might want a simpler gradient or one that reflects the overall level's color
            // Let's generate a gradient from a base color to the current level's color.
            // Or, use the spread like the circular gauge for consistency.
            let color1 = getDefaultColor(for: max(0, currentLevel - 20)) // Bottom/Cooler part of gradient
            let color2 = getDefaultColor(for: currentLevel)              // Middle/Main color
            let color3 = getDefaultColor(for: min(140, currentLevel + 20)) // Top/Warmer part of gradient
            return [color1, color2, color3]
        }
    }

    // Contextual text (copied from CircularGaugeView)
    private func getContextualText(for level: Float) -> String {
        let level = Int(level) // Work with integer decibel levels
        switch level {
        // Home
        case 0..<40: return "Quiet Environment"
        case 40..<50: return "Quiet Office, Library / Quiet Residential Area"
        case 50: return "Refrigerator / Large Office"
        case 51..<55: return "Electric Toothbrush"
        case 55: return "Coffee Percolator / Electric Toothbrush"
        case 56..<60: return "Dishwasher / Electric Toothbrush"
        case 60: return "Sewing Machine / Electric Toothbrush / Vacuum Cleaner / Hair Dryer"
        case 61..<65: return "Vacuum Cleaner / Hair Dryer"
        case 65: return "Alarm Clock / Vacuum Cleaner / Hair Dryer / Power Lawn Mower"
        case 66..<70: return "Alarm Clock / Dishwasher / Vacuum Cleaner / Hair Dryer / Power Lawn Mower"
        case 70: return "TV Audio / Coffee Grinder / Garbage Disposal / Alarm Clock / Dishwasher / Vacuum Cleaner / Hair Dryer / Power Lawn Mower / Freeway Traffic"
        case 71..<75: return "Washing Machine / Air Conditioner / Coffee Grinder / Garbage Disposal / Alarm Clock / Vacuum Cleaner / Hair Dryer / Power Lawn Mower / Freeway Traffic"
        case 75: return "Washing Machine / Air Conditioner / Flush Toilet / Coffee Grinder / Garbage Disposal / Alarm Clock / Vacuum Cleaner / Hair Dryer / Power Lawn Mower / Freeway Traffic"
        case 76..<80: return "Electric Shaver / Flush Toilet / Coffee Grinder / Garbage Disposal / Alarm Clock / Vacuum Cleaner / Hair Dryer / Power Lawn Mower / Freeway Traffic"
        case 80: return "Pop-Up Toaster / Doorbell / Ringing Telephone / Whistling Kettle / Food Mixer or Processor / Blender / Electric Shaver / Flush Toilet / Garbage Disposal / Alarm Clock / Vacuum Cleaner / Hair Dryer / Manual Machine, Tools / Power Lawn Mower / Freeway Traffic"
        case 81..<85: return "Food Mixer or Processor / Blender / Electric Shaver / Flush Toilet / Vacuum Cleaner / Hair Dryer / Manual Machine, Tools / Power Lawn Mower / Heavy Traffic, Noisy Restaurant"
        case 85: return "Handsaw / Food Mixer or Processor / Blender / Vacuum Cleaner / Hair Dryer / Heavy Traffic, Noisy Restaurant / Power Lawn Mower"
        // Work & Recreation
        case 86..<90: return "Food Mixer or Processor / Blender / Hair Dryer / Tractor / Truck, Shouted Conversation / Power Lawn Mower"
        case 90: return "Tractor / Subway / Truck, Shouted Conversation / Hair Dryer / Power Lawn Mower"
        case 91..<95: return "Subway / Electric drill / Hair Dryer / Power Lawn Mower / Motorcycle"
        case 95: return "Electric drill / Power Lawn Mower / Motorcycle"
        case 96..<100: return "Factory Machinery / Woodworking Class / Snowmobile / School Dance, Boom Box / Motorcycle"
        case 100: return "Factory Machinery / Woodworking Class / Snowmobile / School Dance, Boom Box / Motorcycle"
        case 101..<105: return "Snow Blower / Factory Machinery / Woodworking Class / Snowmobile / School Dance, Boom Box / Motorcycle"
        case 105: return "Snow Blower / Factory Machinery / Woodworking Class / Snowmobile / School Dance, Boom Box / Motorcycle"
        case 106..<110: return "Power Saw / Leaf Blower / Subway / Music Club, Disco / Busy Video Arcade / Symphony Concert / Car Horn / Motorcycle / Rock Concert"
        case 110: return "Baby Crying / Squeaky Toy Held Close to Ear / Power Saw / Leaf Blower / Subway / Music Club, Disco / Busy Video Arcade / Symphony Concert / Car Horn / Motorcycle / Rock Concert"
        case 111..<112: return "Subway / Personal Music Player on High / Rock Concert"
        case 112: return "Subway / Personal Music Player on High / Rock Concert"
        case 113..<115: return "Subway / Rock Concert"
        case 115: return "Subway / Rock Concert" // End of subway range
        case 116..<117: return "Football Game Stadium / Rock Concert"
        case 117: return "Football Game Stadium / Rock Concert"
        case 118..<120: return "Rock Concert / Band Concert"
        case 120: return "Chainsaw, Hammer On Nail / Pneumatic Drills, Heavy Machine / Jet Plane at Ramp / Ambulance Siren / Band Concert"
        case 121..<125: return "Chainsaw, Hammer On Nail / Pneumatic Drills, Heavy Machine / Jet Plane at Ramp / Ambulance Siren / Auto Stereo"
        case 125: return "Chainsaw, Hammer On Nail / Pneumatic Drills, Heavy Machine / Jet Plane at Ramp / Ambulance Siren / Auto Stereo"
        case 126..<130: return "Jackhammer, Power Drill / Air Raid / Percussion Section at Symphony / Stock Car Races"
        case 130: return "Jackhammer, Power Drill / Air Raid / Percussion Section at Symphony / Stock Car Races"
        case 131..<135: return "Noisy Squeeze Toys"
        case 135: return "Noisy Squeeze Toys"
        case 136..<140: return "Airplane Taking Off"
        case 140: return "Airplane Taking Off"
        case 141..<143: return "Bicycle Horn"
        case 143: return "Bicycle Horn"
        case 144..<150: return "Firecracker / Jet Engine Taking Off / Artillery Fire at 500 Feet"
        case 150: return "Firecracker / Jet Engine Taking Off / Artillery Fire at 500 Feet"
        case 151..<156: return "Cap Gun"
        case 156: return "Cap Gun"
        case 157: return "Balloon Pop"
        case 158..<162: return "Fireworks (at 3 Feet)"
        case 162: return "Fireworks (at 3 Feet)"
        case 163: return "Rifle"
        case 164..<166: return "Handgun, Shotgun"
        case 166..<170: return "Handgun, Shotgun"
        case 170...188: return "Handgun, Shotgun" // Max for handgun/shotgun up to rocket
        case 189...: return "Rocket Launching from Pad" // From 189 upwards
        default:
            return "Very Loud"
        }
    }

    var body: some View {
        let _ = print("VerticalGaugeView body executing. Level: \(level)")
        GeometryReader { geo in
            let _ = print("VerticalGaugeView GeometryReader executing. Size: \(geo.size)")
            let barWidth = geo.size.width * 0.5 // Example: bar takes 50% of available width
            let barHeight = geo.size.height * 0.7 // Example: bar area takes 70% of available height
            let cornerRadius = barWidth * 0.1 // Dynamic corner radius

            let normalizedLevel = CGFloat(min(max(level / 140, 0), 1)) // Ensure level is between 0 and 1

            ZStack {
                // Background for the gauge
                if let material = styleConfig.gaugeBackgroundMaterial {
                    RoundedRectangle(cornerRadius: cornerRadius * 1.2)
                        .fill(material)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius * 1.2)
                        .fill(styleConfig.gaugeBackgroundColor)
                }

                VStack(spacing: geo.size.height * 0.05) {
                    // dB Level Text (potentially above the bar)
                    Text("\(Int(level)) dB")
                        .font(.system(size: geo.size.width * 0.2, weight: .bold, design: styleConfig.fontDesign ?? .rounded))
                        .foregroundColor(styleConfig.textColor)

                    // Vertical Bar
                    ZStack(alignment: .bottom) {
                        // Background of the bar track
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.gray.opacity(0.3)) // Track color
                            .frame(width: barWidth, height: barHeight)

                        // Filled portion of the bar
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: currentProgressGradientColors),
                                startPoint: .bottom,
                                endPoint: .top
                            ))
                            .frame(width: barWidth, height: barHeight * normalizedLevel)
                    }
                    .frame(width: barWidth, height: barHeight) // Ensure ZStack itself has a defined frame

                    // Contextual Text (potentially below the bar)
                    Text(getContextualText(for: level))
                        .font(.system(size: geo.size.width * 0.08, weight: .medium, design: styleConfig.fontDesign ?? .rounded))
                        .foregroundColor(styleConfig.textColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, geo.size.width * 0.05)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .shadow(
                color: styleConfig.customShadow?.color ?? (styleConfig.showShadow ? Color.black.opacity(0.2) : Color.clear),
                radius: styleConfig.customShadow?.radius ?? (styleConfig.showShadow ? 5 : 0),
                x: styleConfig.customShadow?.x ?? (styleConfig.showShadow ? 0 : 0),
                y: styleConfig.customShadow?.y ?? (styleConfig.showShadow ? 2 : 0)
            )
        }
    }
}

#Preview("Vertical Gauge Default") {
    VerticalGaugeView(level: 75, styleConfig: GaugeStyleConfiguration())
        .frame(width: 100, height: 300) // Example frame for preview
        .padding()
}

#Preview("Vertical Gauge Custom Style") {
    var customConfig = GaugeStyleConfiguration()
    customConfig.textColor = .blue
    customConfig.gaugeBackgroundColor = .yellow.opacity(0.3)
    // customConfig.progressArcColors = [Color.purple, Color.pink] // Example for custom gradient if needed

    return VerticalGaugeView(level: 110, styleConfig: customConfig)
        .frame(width: 120, height: 350)
        .padding()
}
