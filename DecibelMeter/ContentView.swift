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
// private let CAL_OFFSET: Float = -7          // tweak after calibration // Will be moved into AudioMeter
private let SAFE_THRESHOLD: Float = 50      // baby‑safe cut‑off dB
private let FREQ_LABELS: [Int] = [50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]

// MARK: - Audio meter
final class AudioMeter: ObservableObject {
    @Published var calibrationOffset: Float = 0 // Default value, can be configured
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
        print("[AudioMeter] Attempting to start. Current running state: \(running)")
        guard !running else {
            print("[AudioMeter] Already running. Ignoring start call.")
            return
        }

        print("[AudioMeter] Starting with \(numberOfBands) bands.")
        self.numberOfBands = numberOfBands
        // Initialize spectrum array with zeros. This ensures UI has a valid array structure immediately.
        self.spectrum = Array(repeating: 0.00001, count: numberOfBands) // Use a tiny non-zero value to avoid division by zero in visualizer if max is 0

        do {
            try prepareSession()
            let node = engine.inputNode
            let fmt  = node.outputFormat(forBus: 0)

            print("[AudioMeter] Installing tap with buffer size 1024.")
            node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, timestamp in
                // print("[AudioMeter] Audio buffer received at \(timestamp.audioTimeStamp.mSampleTime)")
                self?.process(buf)
            }

            try engine.start()
            running = true
            print("[AudioMeter] Engine started successfully. Running state: \(running)")
        } catch {
            print("[AudioMeter] Audio start error: \(error.localizedDescription)")
            running = false // Ensure running state is false if start fails
        }
    }

    func stop() {
        print("[AudioMeter] Attempting to stop. Current running state: \(running)")
        guard running else {
            print("[AudioMeter] Not running. Ignoring stop call.")
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        print("[AudioMeter] Tap removed.")
        engine.stop()
        running = false
        print("[AudioMeter] Engine stopped. Running state: \(running)")
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
        // Use the calibrationOffset property
        var db = max(20 * log10(rms) + 100 + self.calibrationOffset, 0)
        db = min(db, 140) // Removed *1.4 scaling for more standard dB representation
        level = level*0.75 + db*0.25
        sampleCount += 1; avg += (db-avg)/Float(sampleCount); peak = max(peak, db); minDecibels = Swift.min(minDecibels, db)
        // FFT 60 bins
        var win = [Float](repeating: 0, count: 1024)
        vDSP_vmul(ch, 1, window, 1, &win, 1, 1024)
        var r = [Float](repeating: 0, count: 1024)
        var i = [Float](repeating: 0, count: 1024)
        let zero = [Float](repeating: 0, count: 1024)
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
                            var currentMax = mags[start..<min(end, mags.count)].max() ?? 0

                            // Apply logarithmic scaling to compress dynamic range
                            // Add 1 before log to prevent log(0) or log(<1) issues, then scale.
                            // Adjust the scaling factor (e.g., 20.0) to control the visual compression.
                            // A higher factor means more compression of high values.
                            currentMax = log10(currentMax + 1.0) * 20.0 // Example scaling

                            // Ensure value is non-negative after log scaling
                            currentMax = max(0, currentMax)

                            spec.append(currentMax)
                        }

                        // Further normalize the entire frame so the peak is somewhat consistent if desired,
                        // or apply a global scaling factor. For now, the log scaling per bin is the primary change.
                        // Example: Normalize to a peak of 1.0 if spec is not all zeros.
                        // let specMax = spec.max() ?? 1.0
                        // if specMax > 0 {
                        //    spec = spec.map { $0 / specMax }
                        // }

                        DispatchQueue.main.async {
                            // print("[AudioMeter] Processed spectrum: \(spec.map { String(format: "%.2f", $0) })")
                            self.spectrum = spec
                        }
                    }
                }
            }
        }
    }
}

// MARK: - EQ Settings View
struct EQSettingsView: View {
    @Binding var numberOfBands: Float
    @Binding var calibrationOffset: Float

    // Bindings for ParametricEQVisualizerView
    @Binding var eqLineColor: Color
    @Binding var eqFillColor: Color
    @Binding var eqOpacity: Double
    @Binding var eqLineWidth: CGFloat
    @Binding var eqBackgroundColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 15) { // Increased spacing for better layout
            // General Settings
            Text("General").font(.headline).padding(.top, 5)
            HStack {
                Text("Bands:").frame(width: 100, alignment: .leading)
                Slider(value: $numberOfBands, in: 10...100, step: 1)
                Text("\(Int(numberOfBands))").frame(width: 40, alignment: .trailing)
            }
            HStack {
                Text("Calibrate:").frame(width: 100, alignment: .leading)
                Slider(value: $calibrationOffset, in: -20...20, step: 0.5)
                Text(String(format: "%.1f", calibrationOffset)).frame(width: 40, alignment: .trailing)
            }

            Divider().padding(.vertical, 5)

            // Visualizer Appearance Settings
            Text("Visualizer Appearance").font(.headline)

            ColorPicker("Line Color", selection: $eqLineColor)
                .frame(height: 30) // Adjust height for better spacing

            ColorPicker("Fill Color", selection: $eqFillColor)
                .frame(height: 30)

            ColorPicker("Background Color", selection: $eqBackgroundColor)
                .frame(height: 30)

            HStack {
                Text("Opacity:").frame(width: 100, alignment: .leading)
                Slider(value: $eqOpacity, in: 0.0...1.0, step: 0.05)
                Text(String(format: "%.2f", eqOpacity)).frame(width: 40, alignment: .trailing)
            }

            HStack {
                Text("Line Width:").frame(width: 100, alignment: .leading)
                Slider(value: $eqLineWidth, in: 0.5...10.0, step: 0.5)
                Text(String(format: "%.1f", eqLineWidth)).frame(width: 40, alignment: .trailing)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 5) // Add some padding at the bottom of the Vstack
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
    // @State private var animationSpeed: Double = 0.2 // Adjusted default animation speed - Will be handled by ParametricEQVisualizerView's own animation
    // @State private var lineSmoothness: Int = 3    // Adjusted default line smoothness - Will be handled by ParametricEQVisualizerView
    @State private var calibrationOffsetValue: Float = -7.0 // Default, will sync with meter

    // Parametric EQ Visualizer Settings
    @State private var eqLineColor: Color = .accentColor
    @State private var eqFillColor: Color = .accentColor.opacity(0.3)
    @State private var eqOpacity: Double = 0.8
    @State private var eqLineWidth: CGFloat = 2.0
    @State private var eqBackgroundColor: Color = Color(.systemGray6)


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
                ParametricEQVisualizerView(
                    data: meter.spectrum,
                    lineColor: eqLineColor,
                    fillColor: eqFillColor,
                    opacity: eqOpacity,
                    lineWidth: eqLineWidth,
                    backgroundColor: eqBackgroundColor
                )
                .frame(height: 150) // Increased height for better visualization
                .padding(.horizontal)
                .onChange(of: numberOfBands) { oldValue, newValue in
                    print("[ContentView] numberOfBands changed from \(oldValue) to \(newValue). Current meter running state: \(meter.running)")
                    // Ensure meter is stopped before reconfiguring.
                    // Dispatch to main queue to ensure UI updates and audio operations are coordinated.
                    DispatchQueue.main.async {
                        if meter.running {
                            print("[ContentView] Meter is running. Stopping meter before changing bands.")
                            meter.stop() // Stop the meter
                            // It's crucial that start is only called after stop has completed.
                            // For simplicity here, we rely on the synchronous nature of stop() within this async block.
                            // If stop() were asynchronous itself, further coordination (e.g. completion handler) would be needed.
                            print("[ContentView] Meter stopped. Starting meter with new band count: \(Int(newValue)).")
                            meter.start(numberOfBands: Int(newValue))
                        } else {
                            // If the meter is not running, just update its configuration.
                            // It will use this new band count when it's next started.
                            print("[ContentView] Meter is not running. Updating numberOfBands to \(Int(newValue)) and re-initializing spectrum.")
                            meter.numberOfBands = Int(newValue)
                            // Also update the spectrum array to reflect the new band count for placeholder UI
                            meter.spectrum = Array(repeating: 0.00001, count: Int(newValue))
                        }
                    }
                }

                DisclosureGroup("EQ Settings", isExpanded: $showEQSettings) {
                    // Pass the new EQ settings bindings to EQSettingsView
                    EQSettingsView(
                        numberOfBands: $numberOfBands,
                        calibrationOffset: $calibrationOffsetValue,
                        eqLineColor: $eqLineColor,
                        eqFillColor: $eqFillColor,
                        eqOpacity: $eqOpacity,
                        eqLineWidth: $eqLineWidth,
                        eqBackgroundColor: $eqBackgroundColor
                    )
                    .onChange(of: calibrationOffsetValue) { oldValue, newValue in
                        print("[ContentView] calibrationOffsetValue changed from \(oldValue) to \(newValue).")
                        // This change can be applied directly to the meter whether it's running or not.
                        // It doesn't require restarting the audio engine.
                        meter.calibrationOffset = newValue
                    }
                }
                .padding(.horizontal)
                .onAppear { // Initialize slider value from meter's value
                    // Sync the local state with the meter's initial state only if it hasn't been set yet
                    // or if they differ, to avoid potential issues if this onAppear runs multiple times.
                    // However, direct assignment is usually fine for onAppear.
                    print("[ContentView] onAppear: Initializing calibrationOffsetValue from meter.calibrationOffset (\(meter.calibrationOffset)).")
                    calibrationOffsetValue = meter.calibrationOffset
                }


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
