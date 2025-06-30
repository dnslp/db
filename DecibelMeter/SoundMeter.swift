//
//  Untitled.swift
//  DecibelMeter
//
//  Created by David Nyman on 6/23/25.
//
import AVFoundation
import Combine

class SoundMeter: ObservableObject {
    private let engine = AVAudioEngine()
    @Published var decibels: Float = 0.0

    func start() throws {
        // Audio session setup as before…
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        input.removeTap(onBus: 0)                      // clear old taps
        let format = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            let level = self.getSoundLevel(buffer: buffer)
            DispatchQueue.main.async {
                self.decibels = level
            }
        }

        try engine.start()                              // start engine
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func getSoundLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        let sampleRate = Float(buffer.format.sampleRate)

        // Apply A-weighting filter
        let weightedData = applyAWeighting(data: data, count: count, sampleRate: sampleRate)

        // RMS calculation
        let sumSquares = weightedData.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumSquares / Float(count) + Float.ulpOfOne)
        // dBFS then normalize into 0–100
        let db = 20 * log10(rms)
        return max(db + 100, 0) // clamp at minimum 0
    }

    private func applyAWeighting(data: UnsafeMutablePointer<Float>, count: Int, sampleRate: Float) -> [Float] {
        var weightedData = [Float](repeating: 0, count: count)
        for i in 0..<count {
            // This is a simplified A-weighting calculation.
            // A full implementation would require a more complex filter design.
            // This example focuses on the principle rather than perfect accuracy.
            // The formula for R_A(f) from Wikipedia is:
            // R_A(f) = (12194^2 * f^4) / ((f^2 + 20.6^2) * sqrt((f^2 + 107.7^2) * (f^2 + 737.9^2)) * (f^2 + 12194^2))
            // A(f) = 20 * log10(R_A(f)) - 20 * log10(R_A(1000))
            // For simplicity, we'll use a placeholder weighting.
            // In a real application, you'd implement the actual filter.

            // Placeholder: Reduce volume of low and very high frequencies
            let frequency = Float(i) * sampleRate / Float(count) // Approximate frequency of this sample
            var weight: Float = 1.0

            if frequency < 200 { // Attenuate low frequencies
                weight *= (frequency / 200.0)
            } else if frequency > 6000 { // Attenuate very high frequencies
                weight *= (6000.0 / frequency)
            }

            // Ensure weight is not negative or excessively large
            weight = max(0, min(weight, 1.5))


            weightedData[i] = data[i] * weight
        }
        return weightedData
    }
}
