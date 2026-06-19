//
//  LLMEngine.swift
//  ORB
//
//  Protocol boundary for the multimodal intent/vision model. The shipping
//  implementation is `MLXGemmaEngine`, running Gemma 4 E4B (4-bit) via MLX.
//

import Foundation
import CoreGraphics

@MainActor
protocol LLMEngine: AnyObject {
    var displayName: String { get }
    var isReady: Bool { get }
    /// Real resident footprint contributed by the model, in MB.
    var ramMB: Int { get }
    /// Throughput of the last generation in tokens/second (measured).
    var lastTokensPerSecond: Double { get }

    func load() async throws
    func unload()

    /// Extract a structured intent from the transcript (+ optional screenshot).
    func extractIntent(from transcript: String, screenshot: CGImage?) async -> CommandIntent
    /// Visually verify a step succeeded by reading the screen.
    func verifyStep(_ step: PlannedAction, screenshot: CGImage?) async -> Bool
}
