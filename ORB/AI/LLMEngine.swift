//
//  LLMEngine.swift
//  ORB
//
//  Protocol boundary for the multimodal intent/vision model. Ships with a
//  simulated Gemma 4 E4B that uses ActionPlanner for intent and always
//  "verifies" steps. A real MLX adapter implements the same protocol.
//

import Foundation
import AppKit

@MainActor
protocol LLMEngine: AnyObject {
    var displayName: String { get }
    var isReady: Bool { get }
    var ramMB: Int { get }
    var metric: String { get }        // e.g. "81 tok/s"
    func load() async
    func unload()
    /// Extract structured intent from the transcript (+ optional screenshot).
    func extractIntent(from transcript: String, screenshot: CGImage?) async -> CommandIntent
    /// Visually verify a step succeeded by reading the screen.
    func verifyStep(_ step: PlannedAction, screenshot: CGImage?) async -> Bool
}

@MainActor
final class SimulatedGemmaEngine: LLMEngine {
    let displayName = "Gemma 4 E4B"
    private(set) var isReady = false
    let ramMB = RAMManager.gemmaMB
    let metric = "81 tok/s"

    private let planner = ActionPlanner()

    func load() async {
        // Simulate loading several GB of Q4_K_M weights via MLX.
        try? await Task.sleep(nanoseconds: 600_000_000)
        isReady = true
    }

    func unload() { isReady = false }

    func extractIntent(from transcript: String, screenshot: CGImage?) async -> CommandIntent {
        // Simulate token generation latency proportional to a short plan.
        try? await Task.sleep(nanoseconds: 350_000_000)
        return planner.plan(for: transcript)
    }

    func verifyStep(_ step: PlannedAction, screenshot: CGImage?) async -> Bool {
        try? await Task.sleep(nanoseconds: 120_000_000)
        return true // a real model inspects the screenshot here
    }
}
