//
//  STTEngine.swift
//  ORB
//
//  Protocol boundary for speech-to-text. The app ships with a simulated
//  Moonshine engine that streams partial transcripts word-by-word, exactly
//  like the design. A real MLX/Moonshine adapter can drop in behind this
//  same protocol later without touching the rest of the app.
//

import Foundation
import AVFoundation

@MainActor
protocol STTEngine: AnyObject {
    var displayName: String { get }
    var isReady: Bool { get }
    var ramMB: Int { get }
    /// Load weights into memory (lazy). 107 ms latency target.
    func load() async
    /// Free memory.
    func unload()
    /// Begin a streaming session. `onPartial` fires as words arrive.
    func beginStreaming(onPartial: @escaping (String) -> Void)
    /// Optionally feed a 16 kHz mono PCM chunk (real engines use this).
    func feed(_ chunk: AVAudioPCMBuffer)
    /// Finalize and return the confirmed transcript, then unload.
    func finishStreaming() -> String
}

/// Drop-in simulated Moonshine Small. Produces a realistic live transcript.
@MainActor
final class SimulatedMoonshineSTT: STTEngine {
    let displayName = "Moonshine Small"
    private(set) var isReady = false
    let ramMB = RAMManager.moonshineMB

    private var words: [String] = []
    private var index = 0
    private var timer: Timer?
    private var onPartial: ((String) -> Void)?

    /// The scripted phrase used for the on-device demo transcript.
    var scriptedPhrase = "Open Chrome and search for the latest M4 MacBook reviews"

    func load() async {
        // Simulate the fast load of a 123 MB model.
        try? await Task.sleep(nanoseconds: 120_000_000)
        isReady = true
    }

    func unload() {
        timer?.invalidate(); timer = nil
        isReady = false
    }

    func beginStreaming(onPartial: @escaping (String) -> Void) {
        self.onPartial = onPartial
        words = scriptedPhrase.split(separator: " ").map(String.init)
        index = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.23, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func feed(_ chunk: AVAudioPCMBuffer) {
        // A real engine would run inference on the chunk here.
    }

    private func tick() {
        guard index < words.count else { return }
        index += 1
        onPartial?(words.prefix(index).joined(separator: " "))
    }

    func finishStreaming() -> String {
        timer?.invalidate(); timer = nil
        let full = words.isEmpty ? scriptedPhrase : words.joined(separator: " ")
        unload()
        return full
    }
}
