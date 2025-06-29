//
//  ContentView.swift
//  DecibelMeter
//
//  Created by David Nyman on 6/23/25.
//
import SwiftUI
import UIKit
import AVFoundation
import Accelerate
import AVFAudio

// MARK: - EQ Visualization Settings Structure
struct EQVisualizationSettings: Codable {
    var xScalePowerFactor: CGFloat = 1.5
    var minLineWidth: CGFloat = 1.0
    var maxLineWidth: CGFloat = 5.0
    var lowAmplitudeHue: Double = 0.7  // e.g., Blue/Violet
    var highAmplitudeHue: Double = 0.0 // e.g., Red
    var lowAmplitudeBrightness: Double = 0.7
    var highAmplitudeBrightness: Double = 1.0
    var minOpacity: Double = 0.6
    var maxOpacity: Double = 1.0

    // Add a static default instance for easy initialization
    static let `default` = EQVisualizationSettings()
}

// MARK: - Parameters
private let CAL_OFFSET: Float = -7          // tweak after calibration
private let SAFE_THRESHOLD: Float = 50      // baby‑safe cut‑off dB
private let FREQ_LABELS: [Int] = [50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]

// MARK: - Audio meter
final class AudioMeter: ObservableObject {
    private let engine = AVAudioEngine()
    private let fftSetup = vDSP_DFT_zop_CreateSetup(nil, 1024, .FORWARD)!
    private let window: [Float] = {
        var w = [Float](repeating: 0, count: 1024)
        vDSP_hann_window(&w, 1024, Int32(vDSP_HANN_NORM))
        return w
    }()

    @Published var level: Float = 0   // smoothed 0…140
    @Published var avg:   Float = 0
    @Published var peak:  Float = 0
    @Published var minDecibels: Float = 140 // Renamed from min
    @Published var spectrum: [Float] = Array(repeating: 0, count: 60)

    private var sampleCount = 0
    private var running = false

    // MARK: public API
    func start() {
        guard !running else { return }
        do {
            try prepareSession()
            let node = engine.inputNode
            let fmt  = node.outputFormat(forBus: 0)
            node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
                self?.process(buf)
            }
            try engine.start(); running = true
        } catch { print("Audio start error", error) }
    }
    func stop() {
        guard running else { return }
        engine.stop(); engine.inputNode.removeTap(onBus: 0); running = false
    }

    // Called on scene/background
    func suspend() { if running { engine.pause() } }
    func resume()  { if running { try? engine.start() } }

    // MARK: internals
    private func resetStats() { level = 0; avg = 0; peak = 0; minDecibels = 140; sampleCount = 0 }

    private func prepareSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.record, mode: .measurement)
        try s.setActive(true)
        if let bottom = s.availableInputs?.first(where: { $0.portType == .builtInMic && $0.portName.lowercased().contains("bottom") }) {
            try? s.setPreferredInput(bottom)
        }
    }

    private func process(_ buf: AVAudioPCMBuffer) {
        guard let ch = buf.floatChannelData?[0] else { return }
        let n = Int(buf.frameLength)
        // SPL
        var power: Float = 0; vDSP_measqv(ch, 1, &power, vDSP_Length(n))
        let rms = sqrt(power + Float.ulpOfOne)
        var db = max(20 * log10(rms)+100+CAL_OFFSET, 0)
        db = min(db, 140) // Removed *1.4 scaling for more standard dB representation
        level = level*0.75 + db*0.25
        sampleCount += 1; avg += (db-avg)/Float(sampleCount); peak = max(peak, db); minDecibels = Swift.min(minDecibels, db)
        // FFT 60 bins
        var win = [Float](repeating: 0, count: 1024)
        vDSP_vmul(ch, 1, window, 1, &win, 1, 1024)
        var r = [Float](repeating: 0, count: 1024)
        var i = [Float](repeating: 0, count: 1024)
        var zero = [Float](repeating: 0, count: 1024)
        win.withUnsafeBufferPointer { rp in
            zero.withUnsafeBufferPointer { ip in
                r.withUnsafeMutableBufferPointer { rOut in
                    i.withUnsafeMutableBufferPointer { iOut in
                        vDSP_DFT_Execute(fftSetup, rp.baseAddress!, ip.baseAddress!, rOut.baseAddress!, iOut.baseAddress!)
                        var mags = [Float](repeating: 0, count: 512)
                        var split = DSPSplitComplex(realp: rOut.baseAddress!, imagp: iOut.baseAddress!)
                        vDSP_zvabs(&split, 1, &mags, 1, 512)
                        let step = 512/60
                        var spec: [Float] = []
                        for idx in stride(from: 0, to: 512, by: step) { spec.append(mags[idx..<(idx+step)].max() ?? 0) }
                        DispatchQueue.main.async { self.spectrum = spec }
                    }
                }
            }
        }
    }
}

// MARK: - Spectrum with labels
struct SpectrumView: View {
    let data: [Float]
    @Binding var settings: EQVisualizationSettings // Changed from @State to @Binding

    // Helper to calculate x position with non-linear scaling
    private func xPosition(forFrequency hz: Double, totalWidth: CGFloat, minFreq: Double, maxFreq: Double) -> CGFloat {
        guard minFreq > 0, maxFreq > 0, maxFreq > minFreq else { return 0 }
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let logFreq = log10(hz)

        var normalizedLogPos = (logFreq - logMin) / (logMax - logMin)
        normalizedLogPos = max(0, min(1, normalizedLogPos))

        // Use power factor from settings
        let scaledPos = pow(normalizedLogPos, settings.xScalePowerFactor)

        return totalWidth * scaledPos
    }

    // Helper to map data index to an approximate frequency for scaling
    // This is a simplification; actual FFT bins may not map linearly to these frequencies.
    // Assumes data array covers the frequency range from FREQ_LABELS.first to FREQ_LABELS.last logarithmically.
    private func frequencyForIndex(_ index: Int, totalCount: Int, minFreq: Double = Double(FREQ_LABELS.first ?? 50), maxFreq: Double = Double(FREQ_LABELS.last ?? 20000)) -> Double {
        guard totalCount > 1 else { return minFreq } // Avoid division by zero if only one data point
        let normalizedIndex = CGFloat(index) / CGFloat(totalCount - 1)

        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)

        // Interpolate logarithmically
        let logFreq = logMin + normalizedIndex * (logMax - logMin)

        return pow(10, logFreq)
    }

    private func segmentLineWidth(for amplitude: Float, maxVal: Float) -> CGFloat {
        guard maxVal > 0 else { return settings.minLineWidth }
        let normalizedAmplitude = CGFloat(amplitude / maxVal)
        return settings.minLineWidth + (normalizedAmplitude * (settings.maxLineWidth - settings.minLineWidth))
    }

    private func segmentColor(for amplitude: Float, maxVal: Float) -> Color {
        guard maxVal > 0 else { return Color(hue: settings.lowAmplitudeHue, saturation: 1, brightness: settings.lowAmplitudeBrightness) }
        let normalizedAmplitude = CGFloat(amplitude / maxVal)

        let hue = settings.lowAmplitudeHue - (normalizedAmplitude * (settings.lowAmplitudeHue - settings.highAmplitudeHue))
        let brightness = settings.lowAmplitudeBrightness + (normalizedAmplitude * (settings.highAmplitudeBrightness - settings.lowAmplitudeBrightness))

        return Color(hue: hue, saturation: 1, brightness: brightness) // Assuming saturation is constant for now
    }

    private func segmentOpacity(for amplitude: Float, maxVal: Float) -> Double {
        guard maxVal > 0 else { return settings.minOpacity }
        let normalizedAmplitude = CGFloat(amplitude / maxVal)
        return settings.minOpacity + (normalizedAmplitude * (settings.maxOpacity - settings.minOpacity))
    }

    var body: some View {
        GeometryReader { geo in
            let maxVal = data.max() ?? 1 // Corrected: removed duplicate line
            let yScale = geo.size.height / (maxVal > 0 ? CGFloat(maxVal) : 1)
            let viewWidth = geo.size.width
            let minDisplayFreq = Double(FREQ_LABELS.first ?? 50)
            let maxDisplayFreq = Double(FREQ_LABELS.last ?? 20000)

            ZStack(alignment: .bottomLeading) {
                // Segmented Line Chart
                if data.count > 1 {
                    ForEach(0..<data.count - 1, id: \.self) { i in
                        Path { path in
                            let freq1 = frequencyForIndex(i, totalCount: data.count, minFreq: minDisplayFreq, maxFreq: maxDisplayFreq)
                            let x1 = xPosition(forFrequency: freq1, totalWidth: viewWidth, minFreq: minDisplayFreq, maxFreq: maxDisplayFreq)
                            let y1 = geo.size.height - CGFloat(data[i]) * yScale
                            path.move(to: CGPoint(x: x1, y: y1))

                            let freq2 = frequencyForIndex(i + 1, totalCount: data.count, minFreq: minDisplayFreq, maxFreq: maxDisplayFreq)
                            let x2 = xPosition(forFrequency: freq2, totalWidth: viewWidth, minFreq: minDisplayFreq, maxFreq: maxDisplayFreq)
                            let y2 = geo.size.height - CGFloat(data[i+1]) * yScale
                            path.addLine(to: CGPoint(x: x2, y: y2))
                        }
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [segmentColor(for: data[i], maxVal: maxVal).opacity(segmentOpacity(for: data[i], maxVal: maxVal)),
                                                            segmentColor(for: data[i+1], maxVal: maxVal).opacity(segmentOpacity(for: data[i+1], maxVal: maxVal))]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: segmentLineWidth(for: data[i], maxVal: maxVal)
                        )
                    }
                }

                // Frequency tick labels
                ForEach(FREQ_LABELS, id: \.self) { f in
                    let labelFreq = Double(f)
                    let labelX = xPosition(forFrequency: labelFreq, totalWidth: viewWidth, minFreq: minDisplayFreq, maxFreq: maxDisplayFreq)
                    // Ensure labels are within bounds, slightly offset if at the very edge
                    let clampedX = min(max(labelX, geo.size.width * 0.01), viewWidth * 0.99 - 10)


                    Text(f < 1000 ? "\(f)" : "\(f/1000)k")
                        .font(.caption2).foregroundColor(.secondary)
                        .position(x: clampedX, y: geo.size.height + 12)
                }
            }
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject private var meter = AudioMeter()
    @Environment(\.scenePhase) private var phase
    @State private var micGranted = false
    @State private var running = false

    @State private var eqSettings = EQVisualizationSettings.default
    @State private var showEQSettingsPanel = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                scalableGauge
                stats
                SpectrumView(data: meter.spectrum, settings: $eqSettings) // Pass settings
                    .frame(height: 100)
                    .padding(.horizontal)

                DisclosureGroup("EQ Visualization Settings", isExpanded: $showEQSettingsPanel) {
                    VStack(alignment: .leading, spacing: 10) {
                        // xScalePowerFactor Slider
                        HStack {
                            Text("Scale Power:").frame(width: 120, alignment: .leading)
                            Slider(value: $eqSettings.xScalePowerFactor, in: 0.5...3.0, step: 0.01)
                            Text(String(format: "%.2f", eqSettings.xScalePowerFactor))
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 50, alignment: .trailing)
                        }

                        // Min Line Width Slider
                        HStack {
                            Text("Min Line Width:").frame(width: 120, alignment: .leading)
                            Slider(value: $eqSettings.minLineWidth, in: 0.5...5.0, step: 0.1)
                                .onChange(of: eqSettings.minLineWidth) { newValue, oldValue in
                                    eqSettings.maxLineWidth = max(newValue, eqSettings.maxLineWidth)
                                }
                            Text(String(format: "%.1f", eqSettings.minLineWidth))
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 50, alignment: .trailing)
                        }

                        // Max Line Width Slider
                        HStack {
                            Text("Max Line Width:").frame(width: 120, alignment: .leading)
                            Slider(value: $eqSettings.maxLineWidth, in: 1.0...10.0, step: 0.1)
                                .onChange(of: eqSettings.maxLineWidth) { newValue, oldValue in
                                    eqSettings.minLineWidth = min(newValue, eqSettings.minLineWidth)
                                }
                            Text(String(format: "%.1f", eqSettings.maxLineWidth))
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 50, alignment: .trailing)
                        }

                        // Low Amplitude Hue Slider
                        HStack {
                            Text("Low Amp Hue:").frame(width: 120, alignment: .leading)
                            Slider(value: $eqSettings.lowAmplitudeHue, in: 0.0...1.0, step: 0.01)
                            Text(String(format: "%.2f", eqSettings.lowAmplitudeHue))
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 50, alignment: .trailing)
                        }

                        // High Amplitude Hue Slider
                        HStack {
                            Text("High Amp Hue:").frame(width: 120, alignment: .leading)
                            Slider(value: $eqSettings.highAmplitudeHue, in: 0.0...1.0, step: 0.01)
                            Text(String(format: "%.2f", eqSettings.highAmplitudeHue))
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 50, alignment: .trailing)
                        }

                        // Low Amplitude Brightness Slider
                        HStack {
                            Text("Low Amp Bright:").frame(width: 120, alignment: .leading)
                            Slider(value: $eqSettings.lowAmplitudeBrightness, in: 0.0...1.0, step: 0.01)
                            Text(String(format: "%.2f", eqSettings.lowAmplitudeBrightness))
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 50, alignment: .trailing)
                        }

                        // High Amplitude Brightness Slider
                        HStack {
                            Text("High Amp Bright:").frame(width: 120, alignment: .leading)
                            Slider(value: $eqSettings.highAmplitudeBrightness, in: 0.0...1.0, step: 0.01)
                            Text(String(format: "%.2f", eqSettings.highAmplitudeBrightness))
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 50, alignment: .trailing)
                        }

                        // Min Opacity Slider
                        HStack {
                            Text("Min Opacity:").frame(width: 120, alignment: .leading)
                            Slider(value: $eqSettings.minOpacity, in: 0.0...1.0, step: 0.01)
                                .onChange(of: eqSettings.minOpacity) { newValue, oldValue in
                                    eqSettings.maxOpacity = max(newValue, eqSettings.maxOpacity)
                                }
                            Text(String(format: "%.2f", eqSettings.minOpacity))
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 50, alignment: .trailing)
                        }

                        // Max Opacity Slider
                        HStack {
                            Text("Max Opacity:").frame(width: 120, alignment: .leading)
                            Slider(value: $eqSettings.maxOpacity, in: 0.0...1.0, step: 0.01)
                                .onChange(of: eqSettings.maxOpacity) { newValue, oldValue in
                                    eqSettings.minOpacity = min(newValue, eqSettings.minOpacity)
                                }
                            Text(String(format: "%.2f", eqSettings.maxOpacity))
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 50, alignment: .trailing)
                        }

                    }
                    .padding() // Add padding inside the DisclosureGroup content
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)

                actionButton
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: phase) { oldPhase, newPhase in
            if newPhase == .background { meter.suspend() }
            if newPhase == .active { meter.resume() }
        }
        .task { await requestMic() }
    }

    // MARK: – UI components
    private var header: some View {
        Label(meter.level < SAFE_THRESHOLD ? "Safe Level (Baby)" : "Unsafe Level (Baby)", systemImage: meter.level < SAFE_THRESHOLD ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            .font(.headline)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background { // Layer background effects for glass look
                RoundedRectangle(cornerRadius: 25) // Shape for material and color
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 25)
                    .fill((meter.level < SAFE_THRESHOLD ? Color.green : Color.red).opacity(0.25)) // Color layer
            }
            .foregroundColor(meter.level < SAFE_THRESHOLD ? .green : .red) // Keep text/icon color distinct
            .clipShape(RoundedRectangle(cornerRadius: 25)) // Clip to the new radius
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scalableGauge: some View {

        CircularGaugeView(level: meter.level)
            .frame(width: UIScreen.main.bounds.width * 0.75,
                   height: UIScreen.main.bounds.width * 0.75)

            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5) // Added shadow
    }

    private var stats: some View {
        HStack(spacing: 20) { // Adjusted spacing to accommodate the new box
            statBox("MIN", Int(meter.minDecibels))
            statBox("AVG", Int(meter.avg))
            statBox("MAX", Int(meter.peak))
        }
    }
    private func statBox(_ title: String, _ val: Int) -> some View {
        let color: Color
        switch title {
        case "MIN":
            color = .blue
        case "AVG":
            color = .green
        case "MAX":
            color = .orange
        default:
            color = .gray // Fallback color
        }

        return VStack {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text("\(val)").font(.title).bold().monospacedDigit()
                .foregroundColor(color) // Apply color to the value text
        }
        .padding(16)
        .background(.ultraThinMaterial) // Base material
        .overlay( // Overlay for accent color border or background tint
            RoundedRectangle(cornerRadius: 20)
                .stroke(color.opacity(0.5), lineWidth: 2) // Accent border
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    private var actionButton: some View {
        Group {
            if !micGranted {
                Button("Grant Microphone Access") { Task { await requestMic() } }
            } else if !running {
                Button("Start") { meter.start(); running = true }
            } else {
                Button("Stop") { meter.stop(); running = false }
            }
        }
        .buttonStyle(.borderedProminent)
        .font(.headline)
    }

    // MARK: – Permission helper
    @MainActor private func requestMic() async {
        if #available(iOS 17, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { ok in cont.resume(returning: ok) }
            }
        }
        if micGranted {
            meter.start(); running = true
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewDevice("iPhone 14 Pro")
    }
}
