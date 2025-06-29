//
//  ContentView.swift
//  DecibelMeter
//
//  Created by David Nyman on 6/23/25.
//
import SwiftUI
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
    private func resetStats() { level = 0; avg = 0; peak = 0; sampleCount = 0 }

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
        db = min(db*1.4, 140)
        level = level*0.75 + db*0.25
        sampleCount += 1; avg += (db-avg)/Float(sampleCount); peak = max(peak, db)
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
    var body: some View {
        GeometryReader { geo in
            let barW = geo.size.width / CGFloat(data.count)
            let maxVal = data.max() ?? 1
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: barW*0.2) {
                    ForEach(data.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: barW*0.2)
                            .fill(Color.accentColor.opacity(0.75))
                            .frame(width: barW*0.8, height: geo.size.height * CGFloat(data[i]/maxVal))
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

// MARK: - Main View
struct ContentView: View {
    @StateObject private var meter = AudioMeter()
    @Environment(\.scenePhase) private var phase
    @State private var micGranted = false
    @State private var running = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                scalableGauge
                stats
                SpectrumView(data: meter.spectrum)
                    .frame(height: 100)
                    .padding(.horizontal)
                actionButton
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: phase) { p in
            if p == .background { meter.suspend() }
            if p == .active { meter.resume() }
        }
        .task { await requestMic() }
    }

    // MARK: – UI components
    private var header: some View {
        Label(meter.level < SAFE_THRESHOLD ? "Safe Level (Baby)" : "Unsafe Level (Baby)", systemImage: meter.level < SAFE_THRESHOLD ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            .font(.headline)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background((meter.level < SAFE_THRESHOLD ? Color.green : Color.red).opacity(0.15))
            .foregroundColor(meter.level < SAFE_THRESHOLD ? .green : .red)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scalableGauge: some View {
        GeometryReader { geo in
            Gauge(value: Double(meter.level), in: 0...140) {
                EmptyView()
            } currentValueLabel: {
                Text("\(Int(meter.level)) dB")
                    .font(.system(size: geo.size.width*0.12, weight: .bold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(Gradient(colors: [.green, .yellow, .orange, .red]))
            .frame(width: geo.size.width*2, height: geo.size.width*2)
            .position(x: geo.size.width/2, y: geo.size.height/2)
        }
        .frame(height: 300) // bigger gauge
    }

    private var stats: some View {
        HStack(spacing: 40) {
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
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
