import SwiftUI

// To enable Picker for Material, we need a identifiable wrapper if we want "None" option.
// However, standard Materials are already hashable. We might need a wrapper if we include a "None" case.
// For now, let's assume direct use or a simple enum if "None" is critical.

enum SelectableMaterial: String, CaseIterable, Identifiable, Codable { // Added Codable
    case none = "None"
    case ultraThin = "Ultra Thin"
    case thin = "Thin"
    case regular = "Regular"
    case thick = "Thick"
    case ultraThick = "Ultra Thick" // Corrected from "Ultra Thick Material" to match typical naming

    var id: String { self.rawValue }

    var material: Material? {
        switch self {
        case .none: return nil
        case .ultraThin: return .ultraThinMaterial
        case .thin: return .thinMaterial
        case .regular: return .regularMaterial
        case .thick: return .thickMaterial
        case .ultraThick: return .ultraThickMaterial
        }
    }
}

// Enum for predefined gradient options for progressArcColors
enum PredefinedGradient: String, CaseIterable, Identifiable, Codable { // Added Codable
    case defaultDynamic = "Default Dynamic"
    case oceanBlue = "Ocean Blue"
    case sunsetOrange = "Sunset Orange"
    case forestGreen = "Forest Green"
    case monochromeGlass = "Monochrome Glass"

    var id: String { self.rawValue }

    var colors: [Color]? { // Returns nil for default to use the original dynamic logic
        switch self {
        case .defaultDynamic:
            return nil
        case .oceanBlue:
            return [Color.blue.opacity(0.7), Color.cyan.opacity(0.5), Color.blue.opacity(0.7)]
        case .sunsetOrange:
            return [Color.orange.opacity(0.8), Color.yellow.opacity(0.6), Color.red.opacity(0.8)]
        case .forestGreen:
            return [Color.green.opacity(0.7), Color.yellow.opacity(0.5), Color.green.opacity(0.7)]
        case .monochromeGlass:
            return [Color.white.opacity(0.3), Color.white.opacity(0.1), Color.white.opacity(0.3)]
        }
    }
}

// Enum for Font.Design
enum SelectableFontDesign: String, CaseIterable, Identifiable, Codable { // Added Codable
    case `default` = "Default"
    case rounded = "Rounded"
    case serif = "Serif"
    case monospaced = "Monospaced"

    var id: String { self.rawValue }

    var design: Font.Design? { // Font.Design is not an enum, so map carefully
        switch self {
        case .default: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

// Enum for StrokeLineCap
enum SelectableLineCap: String, CaseIterable, Identifiable, Codable { // Added Codable
    case round = "Round"
    case butt = "Butt"
    case square = "Square"

    var id: String { self.rawValue }

    var lineCap: CGLineCap {
        switch self {
        case .round: return .round
        case .butt: return .butt
        case .square: return .square
        }
    }
}

// Helper struct for Codable Color
struct CodableColor: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(color: Color) {
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var o: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &o)
        self.red = Double(r)
        self.green = Double(g)
        self.blue = Double(b)
        self.opacity = Double(o)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct GaugeStyleConfiguration: Codable { // Added Codable
    // Store CodableColor instead of Color directly
    private var _gaugeBackgroundColor: CodableColor = CodableColor(color: Color.secondary.opacity(0.1))
    var selectedMaterial: SelectableMaterial = .none
    var selectedGradient: PredefinedGradient = .defaultDynamic
    var lineWidth: CGFloat = 15.0
    var selectedLineCap: SelectableLineCap = .round
    var showShadow: Bool = false
    private var _shadowColor: CodableColor = CodableColor(color: Color.black.opacity(0.2))
    var shadowRadius: CGFloat = 5.0
    var shadowX: CGFloat = 0.0
    var shadowY: CGFloat = 2.0
    private var _textColor: CodableColor = CodableColor(color: .primary)
    var selectedFontDesign: SelectableFontDesign = .rounded

    // Public computed properties for Color types, using the private CodableColor properties
    var gaugeBackgroundColor: Color {
        get { _gaugeBackgroundColor.color }
        set { _gaugeBackgroundColor = CodableColor(color: newValue) }
    }
    var shadowColor: Color {
        get { _shadowColor.color }
        set { _shadowColor = CodableColor(color: newValue) }
    }
    var textColor: Color {
        get { _textColor.color }
        set { _textColor = CodableColor(color: newValue) }
    }

    // CodingKeys to manage the private storage properties
    enum CodingKeys: String, CodingKey {
        case _gaugeBackgroundColor = "gaugeBackgroundColor"
        case selectedMaterial
        case selectedGradient
        case lineWidth
        case selectedLineCap
        case showShadow
        case _shadowColor = "shadowColor"
        case shadowRadius
        case shadowX
        case shadowY
        case _textColor = "textColor"
        case selectedFontDesign
    }


    // Computed properties to bridge enums to CircularGaugeView properties
    var gaugeBackgroundMaterial: Material? {
        selectedMaterial.material
    }

    var progressArcColors: [Color]? {
        selectedGradient.colors
    }

    var progressArcStrokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: selectedLineCap.lineCap)
    }

    var customShadow: ShadowStyle? {
        // Only return a shadow style if showShadow is true, to simplify CircularGaugeView logic
        // Or, CircularGaugeView can handle this logic. Let's make it explicit here.
        if showShadow {
            return ShadowStyle(color: shadowColor, radius: shadowRadius, x: shadowX, y: shadowY)
        }
        return nil // if showShadow is false, no custom shadow is applied from these detailed settings
    }

    var fontDesign: Font.Design? {
        selectedFontDesign.design
    }

    // Helper computed property for UI logic
    var isGaugeBackgroundEffectivelyInvisible: Bool {
        // Check if the stored CodableColor's opacity is zero (or very close to it)
        // and no material is selected.
        let isColorInvisible = _gaugeBackgroundColor.opacity < 0.001
        return selectedMaterial == .none && isColorInvisible
    }
}
