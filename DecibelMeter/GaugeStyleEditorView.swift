import SwiftUI

struct GaugeStyleEditorView: View {
    @Binding var config: GaugeStyleConfiguration
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Background Style")) {
                    ColorPicker("Background Color", selection: $config.gaugeBackgroundColor)

                    Picker("Background Material", selection: $config.selectedMaterial) {
                        ForEach(SelectableMaterial.allCases) { materialType in
                            Text(materialType.rawValue).tag(materialType)
                        }
                    }
                    .disabled(config.isGaugeBackgroundEffectivelyInvisible)
                    // A note or logic to clarify that material might override color could be useful depending on CircularGaugeView's rendering logic.
                    // For now, CircularGaugeView prioritizes material if present.
                }

                Section(header: Text("Progress Arc Style")) {
                    Picker("Arc Gradient", selection: $config.selectedGradient) {
                        ForEach(PredefinedGradient.allCases) { gradient in
                            Text(gradient.rawValue).tag(gradient)
                        }
                    }

                    HStack {
                        Text("Line Width")
                        Slider(value: $config.lineWidth, in: 1...50, step: 1)
                        Text("\(Int(config.lineWidth))")
                    }

                    Picker("Line Cap", selection: $config.selectedLineCap) {
                        ForEach(SelectableLineCap.allCases) { cap in
                            Text(cap.rawValue).tag(cap)
                        }
                    }
                }

                Section(header: Text("Shadow Style")) {
                    Toggle("Enable Shadow", isOn: $config.showShadow)

                    if config.showShadow {
                        ColorPicker("Shadow Color", selection: $config.shadowColor)
                        HStack {
                            Text("Radius")
                            Slider(value: $config.shadowRadius, in: 0...20, step: 1)
                            Text(String(format: "%.0f", config.shadowRadius))
                        }
                        HStack {
                            Text("Offset X")
                            Slider(value: $config.shadowX, in: -20...20, step: 1)
                            Text(String(format: "%.0f", config.shadowX))
                        }
                        HStack {
                            Text("Offset Y")
                            Slider(value: $config.shadowY, in: -20...20, step: 1)
                            Text(String(format: "%.0f", config.shadowY))
                        }
                    }
                }

                Section(header: Text("Text Style")) {
                    ColorPicker("Text Color", selection: $config.textColor)
                    Picker("Font Design", selection: $config.selectedFontDesign) {
                        ForEach(SelectableFontDesign.allCases) { design in
                            Text(design.rawValue).tag(design)
                        }
                    }
                }
            }
            .navigationTitle("Edit Gauge Style")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    // Need a State variable to bind to for the preview
    struct PreviewWrapper: View {
        @State private var previewConfig = GaugeStyleConfiguration()
        var body: some View {
            GaugeStyleEditorView(config: $previewConfig)
        }
    }
    return PreviewWrapper()
}
