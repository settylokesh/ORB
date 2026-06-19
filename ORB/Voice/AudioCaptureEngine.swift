//
//  AudioCaptureEngine.swift
//  ORB
//
//  Real microphone capture via AVAudioEngine, downsampled to the 16 kHz mono
//  PCM format Moonshine expects. Emits an RMS level (drives the waveform) and
//  triggers silence detection. The transcribed words come from the STTEngine.
//

import Foundation
import AVFoundation

final class AudioCaptureEngine {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000,
                                             channels: 1,
                                             interleaved: false)!
    let silence = SilenceDetector()

    /// Latest RMS amplitude in 0...1, delivered on the main queue.
    var onLevel: ((Float) -> Void)?
    /// 16 kHz mono PCM chunk, delivered on the main queue (ready for an STT model).
    var onChunk: ((AVAudioPCMBuffer) -> Void)?

    private(set) var isRunning = false

    func start() throws {
        guard !isRunning else { return }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        silence.start()

        input.installTap(onBus: 0, bufferSize: 1600, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        silence.stop()
        isRunning = false
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        // Downsample to 16 kHz mono.
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }

        let level = Self.rms(out)
        let producedChunk = out
        Task { @MainActor in
            self.onLevel?(level)
            self.silence.feed(level: level)
            self.onChunk?(producedChunk)
        }
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { let s = data[i]; sum += s * s }
        return min(1, (sum / Float(n)).squareRoot() * 6) // scaled for display
    }
}
