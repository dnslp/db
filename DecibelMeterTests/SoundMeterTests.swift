//
//  SoundMeterTests.swift
//  DecibelMeterTests
//
//  Created by Jules on 2/9/25.
//

import XCTest
@testable import DecibelMeter
import AVFoundation

class SoundMeterTests: XCTestCase {

    var soundMeter: SoundMeter!

    override func setUpWithError() throws {
        try super.setUpWithError()
        soundMeter = SoundMeter()
    }

    override func tearDownWithError() throws {
        soundMeter = nil
        try super.tearDownWithError()
    }

    func testGetSoundLevelWithSilence() throws {
        // Create a silent audio buffer
        let frameCount: AVAudioFrameCount = 1024
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            XCTFail("Failed to create AVAudioPCMBuffer")
            return
        }
        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<Int(frameCount) {
                channelData[i] = 0.0 // Silence
            }
        }

        let decibels = soundMeter.getSoundLevel(buffer: buffer)
        // For silence, the decibel level should be very low (or -infinity, which our app clamps to 0)
        // We expect a value close to 0 after normalization and clamping.
        // Allowing for small floating point inaccuracies.
        XCTAssertEqual(decibels, 0.0, accuracy: 0.1, "Decibel level for silence should be close to 0.")
    }

    func testApplyAWeighting() throws {
        let frameCount = 1024
        let sampleRate: Float = 44100.0
        var testData = [Float](repeating: 1.0, count: frameCount) // Uniform signal

        // Use a pointer for the UnsafeMutablePointer<Float> argument
        let weightedData = testData.withUnsafeMutableBufferPointer { bufferPointer -> [Float] in
            guard let baseAddress = bufferPointer.baseAddress else {
                XCTFail("Could not get base address of test data buffer")
                return []
            }
            return soundMeter.applyAWeighting(data: baseAddress, count: frameCount, sampleRate: sampleRate)
        }

        XCTAssertEqual(weightedData.count, frameCount, "Weighted data should have the same frame count.")

        // Check a few points based on the simplified weighting logic
        // Low frequency (approx 100 Hz for i close to 23 with 44100Hz/1024 samples)
        // frequency = Float(i) * sampleRate / Float(count)
        // 100 = i * 44100 / 1024 => i = 100 * 1024 / 44100 = 2.32
        let lowFreqIndex = 2 // ~86 Hz
        let midFreqIndex = frameCount / 4 // ~11025 Hz / 2 = ~5512 Hz (well within 200-6000 Hz band)
        let highFreqIndex = frameCount - 10 // Some high frequency

        // Expected behavior: low frequencies are attenuated
        if weightedData.indices.contains(lowFreqIndex) && testData.indices.contains(lowFreqIndex) {
             let originalValueLow = testData[lowFreqIndex]
             let weightedValueLow = weightedData[lowFreqIndex]
             let expectedFrequencyLow = Float(lowFreqIndex) * sampleRate / Float(frameCount)
             let expectedWeightLow = max(0, min(expectedFrequencyLow / 200.0, 1.5))
             XCTAssertEqual(weightedValueLow, originalValueLow * expectedWeightLow, accuracy: 0.01, "Low frequencies should be attenuated according to the simplified formula.")
        } else {
            XCTFail("Index out of bounds for low frequency check")
        }


        // Expected behavior: mid frequencies (200Hz - 6000Hz) are less affected or slightly boosted by placeholder
        if weightedData.indices.contains(midFreqIndex) && testData.indices.contains(midFreqIndex) {
            let originalValueMid = testData[midFreqIndex]
            let weightedValueMid = weightedData[midFreqIndex]
             // In our simplified model, frequencies between 200Hz and 6000Hz have weight 1.0
            XCTAssertEqual(weightedValueMid, originalValueMid * 1.0, accuracy: 0.01, "Mid frequencies should have a weight of 1.0 in the simplified model.")
        } else {
             XCTFail("Index out of bounds for mid frequency check")
        }

        // Expected behavior: high frequencies are attenuated
        if weightedData.indices.contains(highFreqIndex) && testData.indices.contains(highFreqIndex) {
            let originalValueHigh = testData[highFreqIndex]
            let weightedValueHigh = weightedData[highFreqIndex]
            let expectedFrequencyHigh = Float(highFreqIndex) * sampleRate / Float(frameCount)
            let expectedWeightHigh = max(0, min(6000.0 / expectedFrequencyHigh, 1.5))
            XCTAssertEqual(weightedValueHigh, originalValueHigh * expectedWeightHigh, accuracy: 0.01, "High frequencies should be attenuated according to the simplified formula.")
        } else {
            XCTFail("Index out of bounds for high frequency check")
        }
    }
}

// Expose private methods for testing
extension SoundMeter {
    func getSoundLevel(buffer: AVAudioPCMBuffer) -> Float {
        return self.getSoundLevel(buffer: buffer)
    }

    func applyAWeighting(data: UnsafeMutablePointer<Float>, count: Int, sampleRate: Float) -> [Float] {
        return self.applyAWeighting(data: data, count: count, sampleRate: sampleRate)
    }
}
