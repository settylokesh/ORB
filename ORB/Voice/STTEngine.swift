//
//  STTEngine.swift
//  ORB
//
//  Protocol boundary for streaming speech-to-text. The shipping implementation
//  is `MoonshineSTT`, a real on-device ONNX Runtime engine. No simulation.
//

import Foundation
import AVFoundation

@MainActor
protocol STTEngine: AnyObject {
    var displayName: String { get }
    var isReady: Bool { get }
    /// Real resident footprint contributed by the model, in MB.
    var ramMB: Int { get }
    /// Wall-clock latency of the last finalize, in milliseconds (measured).
    var lastLatencyMS: Int { get }

    /// Load weights into memory (lazy).
    func load() async throws
    /// Free memory.
    func unload()

    /// Begin a streaming session. `onPartial` fires with live partial transcripts.
    func beginStreaming(onPartial: @escaping (String) -> Void)
    /// Feed a 16 kHz mono PCM chunk produced by the capture engine.
    func feed(_ chunk: AVAudioPCMBuffer)
    /// Finalize and return the confirmed transcript.
    func finishStreaming() async -> String
}
