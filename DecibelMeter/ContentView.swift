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

    private var sampleRate: Double = 48000.0 // Default sample rate, will be updated in start()
    private var sampleCount = 0
    private var running = false

    // Function to calculate A-weighting for a given frequency
    private func getAWeighting(frequency: Float) -> Float {
        if frequency == 0 { return -200.0 } // Avoid log(0) and large attenuation for DC

        let f2 = frequency * frequency
        let f4 = f2 * f2

        // Numerator term for R_A(f)
        let num = pow(12194.0, 2.0) * f4

        // Denominator terms for R_A(f)
        let den1 = f2 + pow(20.6, 2.0)
        let den2_term1 = f2 + pow(107.7, 2.0)
        let den2_term2 = f2 + pow(737.9, 2.0)
        let den2 = sqrt(den2_term1 * den2_term2)
        let den3 = f2 + pow(12194.0, 2.0)

        // Check for zero denominator to avoid division by zero
        if den1 == 0 || den2 == 0 || den3 == 0 {
            return -200.0 // Large attenuation if any part of denominator is zero
        }

        let r_a = num / (den1 * den2 * den3)

        if r_a == 0 {
            return -200.0 // Large attenuation if r_a is zero
        }

        let a_db = 20 * log10(r_a) + 2.00

        // The A-weighting curve can produce very large negative values at low frequencies.
        // Some implementations cap this at a certain level, e.g. -70dB or -80dB.
        // For now, we'll return the calculated value.
        return a_db
    }

    // MARK: public API
    func start(numberOfBands: Int = 60) { // Accept numberOfBands
        guard !running else { return }
        self.numberOfBands = numberOfBands
        self.spectrum = Array(repeating: 0, count: numberOfBands) // Initialize spectrum with correct size
        do {
            try prepareSession()
            let node = engine.inputNode
            let fmt  = node.outputFormat(forBus: 0)
            self.sampleRate = fmt.sampleRate // Store the actual sample rate
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
        // Original SPL calculation (broadband, non-A-weighted) is effectively replaced by A-weighted calculation from spectrum

        // FFT
        var win = [Float](repeating: 0, count: 1024) // Buffer for windowed signal
        vDSP_vmul(ch, 1, window, 1, &win, 1, 1024) // Apply Hann window

        // Prepare for FFT
        var realIn = [Float](repeating: 0, count: 1024)
        var imagIn = [Float](repeating: 0, count: 1024) // Imaginary part is zero for real input
        var realOut = [Float](repeating: 0, count: 1024)
        var imagOut = [Float](repeating: 0, count: 1024)

        // Copy windowed signal to real input buffer for FFT
        // vDSP_DFT_Execute expects input in specific layout if using real-to-complex,
        // but here we use complex-to-complex DFT (zop) with imagIn as zeros.
        realIn.withUnsafeMutableBufferPointer { rp in
            win.withUnsafeBufferPointer { winP in
                memcpy(rp.baseAddress, winP.baseAddress, 1024 * MemoryLayout<Float>.size)
            }
        }

        // Perform FFT
        realIn.withUnsafeBufferPointer { rp_unsafe in
            imagIn.withUnsafeBufferPointer { ip_unsafe in
                realOut.withUnsafeMutableBufferPointer { rOut_unsafe in
                    imagOut.withUnsafeMutableBufferPointer { iOut_unsafe in
                        vDSP_DFT_Execute(fftSetup, rp_unsafe.baseAddress!, ip_unsafe.baseAddress!, rOut_unsafe.baseAddress!, iOut_unsafe.baseAddress!)
                    }
                }
            }
        }

        var rawMagnitudes = [Float](repeating: 0, count: 512)
        var splitComplex = DSPSplitComplex(realp: realOut.withUnsafeMutableBufferPointer { $0.baseAddress! },
                                           imagp: imagOut.withUnsafeMutableBufferPointer { $0.baseAddress! })
        vDSP_zvabs(&splitComplex, 1, &rawMagnitudes, 1, 512) // Calculate magnitudes of FFT output bins

        // A-weighting and overall dBA calculation
        var totalAWeightedPower: Float = 0.0
        var magsAWeighted = [Float](repeating: 0, count: 512)
        let nyquistFrequency = Float(self.sampleRate) / 2.0

        for k in 0..<512 { // Iterate through FFT bins (0 to N/2 - 1)
            let frequency = Float(k) * Float(self.sampleRate) / 1024.0 // Center frequency of bin k

            // Ensure frequency does not exceed Nyquist to avoid issues with weighting function if it's not defined beyond
            // Though for A-weighting, it's generally fine.
            let currentFrequency = min(frequency, nyquistFrequency)

            let aWeightDB = self.getAWeighting(frequency: currentFrequency)
            let linearWeight = pow(10.0, aWeightDB / 20.0)

            // It's important to correctly scale FFT magnitudes.
            // For vDSP_DFT_Execute (zop), the output is not normalized by default.
            // A common normalization for power is 1/N^2, or 1/N for amplitude.
            // Here, rawMagnitudes[k] is an amplitude.
            // Let's scale by 1/N (N=1024) for amplitude, then square for power.
            // The vDSP_zvabs result is already sqrt(real^2 + imag^2).
            // The scaling factor for DFT to match RMS power of input needs care.
            // If input signal was pure sine of amplitude A, its RMS is A/sqrt(2).
            // Its FFT peak (single bin) would be A * N / 2 (for one-sided spectrum from zop).
            // For now, let's use magnitudes as they are and see if `+100` offset is still relevant.
            // The division by N (or N/2) is often part of converting FFT output to physical units (like Pa for SPL).
            // Let's assume rawMagnitudes are proportional to amplitude in each band.
            // Power is proportional to amplitude squared.

            let scaledMag = rawMagnitudes[k] / 1024.0 // Basic scaling for N=1024 point FFT
                                                      // This scaling makes the FFT magnitudes smaller.
                                                      // This might require adjusting the `+100` offset later or finding a better scaling factor.

            let weightedMag = scaledMag * linearWeight
            magsAWeighted[k] = weightedMag // Store for spectrum display
            totalAWeightedPower += pow(weightedMag, 2.0)
        }

        // Calculate overall A-weighted SPL (dBA)
        // totalAWeightedPower is sum of squared scaled&weighted magnitudes.
        // This is proportional to the A-weighted power.
        // To convert to dB, 10 * log10(Power) or 20 * log10(RMS_Amplitude)
        // If totalAWeightedPower is treated as "Power_A_weighted_scaled"

        // The original code used: rms = sqrt(power_from_vDSP_measqv); db = 20*log10(rms) + 100
        // If we define rmsA = sqrt(totalAWeightedPower), this is problematic because totalAWeightedPower is a sum over many bins.
        // It's more like totalAWeightedPower is already the "power" term, scaled differently.
        // Let's try to keep the structure similar:
        // If totalAWeightedPower is analogous to `power` from vDSP_measqv, then:
        // let rmsA_equivalent = sqrt(totalAWeightedPower + Float.ulpOfOne)
        // let db_A = 20 * log10(rmsA_equivalent) + 100 + self.calibrationOffset + 10.0
        // The scaling of rawMagnitudes[k] by /1024.0 is crucial here.
        // If totalAWeightedPower is very small due to this scaling, db_A will be very low.
        // Let's use a reference scaling factor. The `+100` implies dBFS where 0dBFS is max level.
        // The vDSP_measqv result `power` is sum of squares of samples / N.
        // The sum of squares of FFT magnitudes (Parseval's theorem) should be related.
        // Sum_k (Mag_k)^2 / N^2 = Sum_n (x_n)^2 / N  (approx, for one-sided spectrum & N scaling)
        // So totalAWeightedPower (using Mag_k/N) is like Sum_k (Mag_k/N)^2.
        // This is sum_power_per_bin.
        // Let's assume totalAWeightedPower is now the A-weighted power, comparable to original `power`
        // if N=1, but since N=1024, and we summed 512 bins.
        // This part is the trickiest and usually requires careful calibration or known reference.

        // For now, let's proceed with totalAWeightedPower being the sum of (scaled_mag * weight)^2
        // And treat it as the new "power" measure.
        let rmsA_from_spectrum = sqrt(totalAWeightedPower + Float.ulpOfOne) // This isn't quite RMS of signal, but related to total A-weighted power

        // The crucial part: relating rmsA_from_spectrum to an SPL value.
        // The original `20 * log10(rms) + 100` converted a unitless RMS (0 to 1 for full scale) to dB (0-100 range).
        // rmsA_from_spectrum needs to be in a similar unitless range (0 to 1) if +100 is to make sense.
        // The rawMagnitudes from vDSP_zvabs are such that for a full-scale sine wave (amplitude 1.0),
        // the peak bin magnitude is N/2 = 512. After scaling by /1024, it's 0.5.
        // Squaring this gives 0.25. Summing these (if it were broadband noise) would be larger.
        // This suggests rmsA_from_spectrum (derived from mags/1024) might be in a range somewhat compatible with the 0-1 idea.

        var db_A = 20 * log10(rmsA_from_spectrum + Float.ulpOfOne) + 100 + self.calibrationOffset + 10.0
        // If rmsA_from_spectrum is too small, db_A will be very negative, then max(0,...) clamps it.
        // This is a common area for needing empirical adjustment of the constant offset (the `+100` part or a new one).

        db_A = max(db_A, 0)
        db_A = min(db_A, 140) // Cap at 140 dB

        // Update published level and stats on the main thread
        let final_db_A = db_A // Use a final capture for the async block
        DispatchQueue.main.async {
            self.level = self.level*0.75 + final_db_A*0.25 // Smoothing
            self.sampleCount += 1 // sampleCount is not @Published, but accessed on main thread if avg/peak/min are.
                                 // Better to update it here if it's involved in calculations for other @Published vars.
                                 // Or, pass final_db_A to main thread and do all calculations there.
                                 // For simplicity here, let's assume sampleCount is mainly for avg.

            // If sampleCount is used to calculate avg, it needs to be consistent.
            // Let's make a local calculation for newAvg and update.
            let newAvg = self.avg + (final_db_A - self.avg) / Float(self.sampleCount) // Calculate new average

            self.avg = newAvg
            self.peak = max(self.peak, final_db_A)
            self.minDecibels = Swift.min(self.minDecibels, final_db_A)
        }

        // Update spectrum display data using A-weighted magnitudes
        // The magsAWeighted are already scaled by N=1024 and weighted.
        // The spectrum view normalizes by its own maxVal, so absolute scale of these is less critical for shape.
        let step = 512 / self.numberOfBands
        var spec: [Float] = []
        for i_band in 0..<self.numberOfBands {
            let startBin = i_band * step
            let endBin = (i_band + 1) * step
            // Ensure we don't go out of bounds for magsAWeighted
            let bandMags = magsAWeighted[startBin..<min(endBin, magsAWeighted.count)]
            let currentMaxInBand = bandMags.max() ?? 0 // Max magnitude in this band
            spec.append(currentMaxInBand)
        }
        DispatchQueue.main.async { self.spectrum = spec }
    }
}

// MARK: - EQ Settings View
struct EQSettingsView: View {
    @Binding var numberOfBands: Float
    @Binding var animationSpeed: Double // Example: 0.1 to 1.0
    @Binding var lineSmoothness: Int    // Example: 1 to 10
    @Binding var calibrationOffset: Float // Added for calibration

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
                HStack {
                    Text("Calibrate:").frame(width: 80, alignment: .leading)
                    Slider(value: $calibrationOffset, in: -20...20, step: 0.5) // Example range, adjust as needed
                    Text(String(format: "%.1f", calibrationOffset)).frame(width: 40, alignment: .trailing) // Adjusted width
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
    @State private var calibrationOffsetValue: Float = -7.0 // Default, will sync with meter

    // AppStorage for the gauge style configuration
    @AppStorage("gaugeStyleConfig") private var gaugeStyleConfigData: Data?
    @State private var gaugeStyleConfig: GaugeStyleConfiguration = GaugeStyleConfiguration() // This will be our working copy
    @State private var showGaugeStyleEditor = false

    // State for sound category selection
    @State private var selectedSoundCategory: SoundCategory = .home


    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                customizableGauge // Renamed from scalableGauge
                stats

                Picker("Contextual Sound Category", selection: $selectedSoundCategory) {
                    ForEach(SoundCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

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
                        lineSmoothness: $lineSmoothness,
                        calibrationOffset: $calibrationOffsetValue
                    )
                    .onChange(of: calibrationOffsetValue) { oldValue, newValue in
                        meter.calibrationOffset = newValue
                    }
                }
                .padding(.horizontal)
                .onAppear { // Initialize slider value from meter's value
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
                    fontDesign: gaugeStyleConfig.fontDesign,
                    selectedCategory: selectedSoundCategory // Pass the selected category
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
