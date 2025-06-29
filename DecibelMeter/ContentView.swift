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
    @Published var minDecibels: Float = Float.greatestFiniteMagnitude
    @Published var spectrum: [Float] = Array(repeating: 0, count: 60) // Default, will be updated
    @Published var numberOfBands: Int = 60 // Default, configurable

    private var sampleCount = 0
    private var running = false

    // MARK: public API
    func start(numberOfBands: Int = 60) { // Accept numberOfBands
        guard !running else { return }
        self.numberOfBands = numberOfBands
        self.spectrum = Array(repeating: 0, count: numberOfBands) // Initialize spectrum with correct size
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
    func resetStats() { level = 0; avg = 0; peak = 0; minDecibels = Float.greatestFiniteMagnitude; sampleCount = 0 }

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
                        // Use the numberOfBands from the published property
                        let step = 512 / self.numberOfBands
                        var spec: [Float] = []
                        for i in 0..<self.numberOfBands {
                            let start = i * step
                            let end = (i + 1) * step
                            // Ensure we don't go out of bounds for mags
                            let currentMax = mags[start..<min(end, mags.count)].max() ?? 0
                            spec.append(currentMax)
                        }
                        DispatchQueue.main.async { self.spectrum = spec }
                    }
                }
            }
        }
    }
}

// MARK: - EQ Settings View
struct EQSettingsView: View {
    @Binding var numberOfBands: Float
    @Binding var animationSpeed: Double // Example: 0.1 to 1.0
    @Binding var lineSmoothness: Int    // Example: 1 to 10

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 10) { // Align text to leading, add spacing
                HStack {
                    Text("Bands:").frame(width: 80, alignment: .leading) // Fixed width for label
                    Slider(value: $numberOfBands, in: 10...100, step: 1)
                    Text("\(Int(numberOfBands))").frame(width: 30, alignment: .trailing) // Fixed width for value
                }
                HStack {
                    Text("Speed:").frame(width: 80, alignment: .leading)
                    Slider(value: $animationSpeed, in: 0.1...1.0, step: 0.1)
                    Text(String(format: "%.1f", animationSpeed)).frame(width: 30, alignment: .trailing)
                }
                HStack {
                    Text("Smoothness:").frame(width: 80, alignment: .leading)
                    Slider(value: .init(get: { Float(lineSmoothness) }, set: { lineSmoothness = Int($0) }), in: 1...10, step: 1)
                    Text("\(lineSmoothness)").frame(width: 30, alignment: .trailing)
                }
            }
            .padding(.vertical, 5) // Reduced vertical padding inside the group
        }
        .padding(.horizontal) // Keep horizontal padding for the DisclosureGroup itself
    }
}

// MARK: - Spectrum with labels
struct SpectrumView: View {
    let data: [Float]
    var animationSpeed: Double
    var lineSmoothness: Int // Higher value means smoother, less segmented lines

    var body: some View {
        GeometryReader { geo in
            if data.isEmpty {
                Text("No data") // Handle empty data case
            } else {
                let barW = geo.size.width / CGFloat(data.count)
                let maxVal = data.max() ?? 1
                // Adjust corner radius based on lineSmoothness.
                // Smaller barW might need smaller radius.
                let cornerRadiusFactor = CGFloat(lineSmoothness) / 10.0 // Normalize smoothness to 0.1 - 1.0
                let cornerRadius = barW * 0.2 * cornerRadiusFactor

                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: barW * 0.2) {
                        ForEach(data.indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(Color.accentColor.opacity(0.75))
                                .frame(width: barW * 0.8, height: geo.size.height * CGFloat(data[i] / maxVal))
                                .animation(.linear(duration: animationSpeed), value: data[i]) // Apply animation
                        }
                    }
                    // Frequency tick labels
                    ForEach(FREQ_LABELS, id: \.self) { f in
                        let x = geo.size.width * CGFloat(log10(Double(f)/50)/log10(400)) // crude log mapping
                        Text(f < 1000 ? "\(f)" : "\(f/1000)k")
                            .font(.caption2).foregroundColor(.secondary)
                            .position(x: x, y: geo.size.height+10)
                    }
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

    // EQ Settings state variables
    @State private var showEQSettings = false
    @State private var numberOfBands: Float = 60 // Default value, matching current spectrum
    @State private var animationSpeed: Double = 0.2 // Adjusted default animation speed
    @State private var lineSmoothness: Int = 3    // Adjusted default line smoothness

    // AppStorage for the gauge style configuration
    @AppStorage("gaugeStyleConfig") private var gaugeStyleConfigData: Data?
    @State private var gaugeStyleConfig: GaugeStyleConfiguration = GaugeStyleConfiguration() // This will be our working copy
    @State private var showGaugeStyleEditor = false


    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                customizableGauge // Renamed from scalableGauge
                stats
                SpectrumView(data: meter.spectrum, animationSpeed: animationSpeed, lineSmoothness: lineSmoothness)
                    .frame(height: 100)
                    .padding(.horizontal)
                    .onChange(of: numberOfBands) { oldValue, newValue in
                        // Restart meter with new number of bands if it's running
                        if running {
                            meter.stop()
                            meter.start(numberOfBands: Int(newValue))
                        } else {
                            // Update the meter's band count even if not running, so it starts with the new value
                            meter.numberOfBands = Int(newValue)
                            meter.spectrum = Array(repeating: 0, count: Int(newValue))
                        }
                    }

                DisclosureGroup("EQ Settings", isExpanded: $showEQSettings) {
                    EQSettingsView(
                        numberOfBands: $numberOfBands,
                        animationSpeed: $animationSpeed,
                        lineSmoothness: $lineSmoothness
                    )
                }
                .padding(.horizontal)

                actionButton
                resetButton

                Button("Edit Gauge Style") {
                    showGaugeStyleEditor = true
                }
                .buttonStyle(.bordered)
                .padding(.top)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showGaugeStyleEditor) {
            GaugeStyleEditorView(config: $gaugeStyleConfig)
                .onDisappear {
                    saveGaugeConfig()
                }
        }
        .onAppear {
            loadGaugeConfig()
        }
        .onChange(of: phase) { oldPhase, newPhase in
            if newPhase == .background { meter.suspend(); saveGaugeConfig() } // Save on backgrounding
            if newPhase == .active { meter.resume() }
        }
        .task { await requestMic(initialBands: Int(numberOfBands)) } // Pass initial bands
    }

    // MARK: - Config Persistence
    private func loadGaugeConfig() {
        guard let data = gaugeStyleConfigData else { return }
        do {
            gaugeStyleConfig = try JSONDecoder().decode(GaugeStyleConfiguration.self, from: data)
        } catch {
            print("Error decoding gaugeStyleConfig: \(error)")
            // Optionally, reset to default or handle error
        }
    }

    private func saveGaugeConfig() {
        do {
            gaugeStyleConfigData = try JSONEncoder().encode(gaugeStyleConfig)
        } catch {
            print("Error encoding gaugeStyleConfig: \(error)")
        }
    }

    // MARK: – UI components
    private func colorForValue(_ value: Int) -> Color {
        if value <= 50 {
            return .green
        } else if value <= 70 {
            return .yellow
        } else {
            return .red
        }
    }

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

    private var customizableGauge: some View { // Renamed
        Group {
            switch gaugeStyleConfig.displayType {
            case .circular:
                CircularGaugeView(
                    level: meter.level,
                    gaugeBackgroundColor: gaugeStyleConfig.gaugeBackgroundColor,
                    gaugeBackgroundMaterial: gaugeStyleConfig.gaugeBackgroundMaterial,
                    progressArcColors: gaugeStyleConfig.progressArcColors,
                    progressArcStrokeStyle: gaugeStyleConfig.progressArcStrokeStyle,
                    showShadow: gaugeStyleConfig.showShadow,
                    customShadow: gaugeStyleConfig.customShadow,
                    textColor: gaugeStyleConfig.textColor,
                    fontDesign: gaugeStyleConfig.fontDesign
                )
                .frame(width: UIScreen.main.bounds.width * 0.75,
                       height: UIScreen.main.bounds.width * 0.75)
            case .vertical:
                VerticalGaugeView(
                    level: meter.level,
                    styleConfig: gaugeStyleConfig
                )
                // For vertical, we might want a different aspect ratio, e.g., taller.
                // Let's start with a similar width but potentially more height, or let it be more flexible.
                // Using a fixed height for now, similar to circular, for consistency in the layout.
                // This can be adjusted based on visual results.
                .frame(width: UIScreen.main.bounds.width * 0.5, // Narrower for vertical
                       height: UIScreen.main.bounds.width * 0.75) // Similar height
            }
        }
        // The background, clipShape and shadow here were for the container of the gauge.
        // The new styling applies *inside* the CircularGaugeView.
        // We might want to keep a container background for contrast, or remove it if the gauge's own bg is sufficient.
        // For now, let's remove the explicit container styling to let the gauge's style shine.
        // .background(.ultraThinMaterial) // This would be behind the gauge's own background
        // .clipShape(Circle())
        // .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
    }

    private var stats: some View {
        HStack(spacing: 20) { // Reduced spacing to accommodate three items
            statBox("MIN", Int(meter.minDecibels == Float.greatestFiniteMagnitude ? 0 : meter.minDecibels)) // Display 0 if minDecibels is still initial value
            statBox("AVG", Int(meter.avg))
            statBox("MAX", Int(meter.peak))
        }
    }
    private func statBox(_ title: String, _ val: Int) -> some View {
        VStack {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text("\(val)").font(.title).bold().monospacedDigit()
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20)) // Increased corner radius
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(colorForValue(val), lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4) // Added shadow
    }

    private var actionButton: some View {
        Group {
            if !micGranted {
                Button("Grant Microphone Access") { Task { await requestMic(initialBands: Int(numberOfBands)) } }
            } else if !running {
                Button("Start") { meter.start(numberOfBands: Int(numberOfBands)); running = true }
            } else {
                Button("Stop") { meter.stop(); running = false }
            }
        }
        .buttonStyle(.borderedProminent)
        .font(.headline)
    }

    private var resetButton: some View {
        Button("Reset Stats") {
            meter.resetStats()
        }
        .buttonStyle(.bordered) // Using a different style to distinguish from Start/Stop
        .font(.headline)
    }

    // MARK: – Permission helper
    @MainActor private func requestMic(initialBands: Int) async {
        if #available(iOS 17, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { ok in cont.resume(returning: ok) }
            }
        }
        if micGranted {
            meter.start(numberOfBands: initialBands); running = true
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
