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
        // RMS calculation
        let sumSquares = (0..<count).reduce(0) { $0 + data[$1] * data[$1] }
        let rms = sqrt(sumSquares / Float(count) + Float.ulpOfOne)
        // dBFS then normalize into 0–100
        let db = 20 * log10(rms)
        return max(db + 100, 0)                         // clamp at minimum 0
    }
}
