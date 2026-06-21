//
//  LiteRTGemmaEngine.swift
//  ORB
//
//  Vision + intent engine for the Gemma 4 E2B model Google ships in the AI Edge
//  Gallery — the `gemma-4-E2B-it.litertlm` bundle (~2.54 GB), run on Google's
//  LiteRT-LM runtime instead of MLX. Takes the transcript and a screenshot and
//  asks the model for the same structured JSON action plan as the MLX engine, so
//  the rest of the pipeline (parsing, execution, verification) is unchanged.
//
//  LiteRT-LM ships as a LOCAL Swift package vendored at ThirdParty/LiteRTLM (its
//  required `-all_load` unsafe linker flag makes Xcode reject it as a *remote*
//  SwiftPM product — a local package is exempt). The macOS xcframework still
//  downloads automatically from the GitHub release on first resolve, so a fresh
//  clone needs no setup. Calls are still wrapped in `#if canImport(LiteRTLM)` as a
//  belt-and-braces guard; in practice the module is always present.
//
//  `Engine` is a Swift `actor`, so `initialize()` / `createConversation()` are
//  awaited cross-actor and run on a background executor — heavy model loading and
//  inference never block the main thread.
//

import Foundation
import CoreGraphics
import AppKit

#if canImport(LiteRTLM)
import LiteRTLM
#endif

@MainActor
final class LiteRTGemmaEngine: LLMEngine {

    let displayName = "Gemma 4 E2B"
    private(set) var isReady = false
    private(set) var isLoading = false
    private(set) var ramMB = 0
    private(set) var lastTokensPerSecond: Double = 0

    private let models: ModelManager
    private let fallback = ActionPlanner()
    private var loadTask: Task<Void, Error>?

    #if canImport(LiteRTLM)
    private var engine: Engine?
    #endif

    init(models: ModelManager) { self.models = models }

    // MARK: - Lifecycle

    func load() async throws {
        if isReady { return }
        if let loadTask { try await loadTask.value; return }
        isLoading = true
        let task = Task { @MainActor [self] in try await reallyLoad() }
        loadTask = task
        defer { loadTask = nil; isLoading = false }
        try await task.value
    }

    /// Background preload used by the warm-on-intent path. Swallows errors (a
    /// failed warm-up just means the first command loads inline, as before).
    func warmUp() async { try? await load() }

    func unload() {
        #if canImport(LiteRTLM)
        engine = nil
        #endif
        isReady = false
        ramMB = 0
    }

    #if canImport(LiteRTLM)
    private func reallyLoad() async throws {
        guard engine == nil else { isReady = true; return }
        guard let url = models.gemmaModelFileURL(.e2b),
              FileManager.default.fileExists(atPath: url.path) else {
            throw ORBError.modelNotDownloaded(displayName)
        }
        let before = ProcessRAM.residentMB()
        // `Engine` is an actor, so initialize() runs on the actor's own (background)
        // executor — awaiting it here maps and prepares ~2.5 GB of weights without
        // blocking the main thread. GPU (Metal) runs the language model, CPU the
        // vision encoder — LiteRT-LM's recommended Apple-silicon mix.
        let config = try EngineConfig(modelPath: url.path,
                                      backend: .gpu,
                                      visionBackend: .cpu(),
                                      cacheDir: NSTemporaryDirectory())
        let engine = Engine(engineConfig: config)
        try await engine.initialize()
        self.engine = engine
        ramMB = max(0, ProcessRAM.residentMB() - before)
        isReady = true
    }
    #else
    private func reallyLoad() async throws {
        throw ORBError.runtimeUnavailable(
            "Gemma 4 E2B needs the LiteRT-LM runtime. Add the Swift package " +
            "github.com/google-ai-edge/LiteRT-LM in Xcode (File ▸ Add Package " +
            "Dependencies), then rebuild.")
    }
    #endif

    // MARK: - Intent extraction

    func extractIntent(from transcript: String, screenshot: CGImage?) async -> CommandIntent {
        #if canImport(LiteRTLM)
        guard let engine else { return fallback.plan(for: transcript) }
        // LiteRT-LM applies the model's chat template per message; fold ORB's
        // system instructions into the prompt so behaviour matches the MLX engine.
        let prompt = """
        \(MLXGemmaEngine.systemPrompt)

        User said: "\(transcript)"

        Return ONLY the JSON action plan.
        """
        var imagePath: String?
        defer { if let p = imagePath { try? FileManager.default.removeItem(atPath: p) } }
        do {
            let conversation = try await engine.createConversation()
            let start = Date()
            let message: Message
            if let cg = screenshot, let path = Self.writeTempImage(cg) {
                imagePath = path
                message = Message(contents: [.imageFile(path), .text(prompt)])
            } else {
                message = Message(contents: [.text(prompt)])
            }
            let reply = try await conversation.sendMessage(message).toString
            measureThroughput(reply, elapsed: Date().timeIntervalSince(start))
            if let intent = MLXGemmaEngine.parsePlan(reply, transcript: transcript) {
                return intent
            }
        } catch {
            // fall through to the rule-based planner
        }
        #endif
        return fallback.plan(for: transcript)
    }

    // MARK: - Visual verification

    func verifyStep(_ step: PlannedAction, screenshot: CGImage?) async -> Bool {
        #if canImport(LiteRTLM)
        guard let engine, let cg = screenshot, let path = Self.writeTempImage(cg) else { return true }
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let conversation = try await engine.createConversation()
            let q = "You verify UI automation. Looking at this screenshot, did this " +
                    "step succeed: \"\(step.title)\"? Answer with exactly YES or NO."
            let reply = try await conversation.sendMessage(
                Message(contents: [.imageFile(path), .text(q)])).toString
            return reply.uppercased().contains("YES")
        } catch {
            return true   // don't block automation on a verification hiccup
        }
        #else
        return true
        #endif
    }

    // MARK: - Helpers

    /// Rough tokens/sec: LiteRT-LM doesn't surface a token count here, so estimate
    /// from the reply length (~4 chars/token) just to drive the dashboard metric.
    private func measureThroughput(_ reply: String, elapsed: TimeInterval) {
        guard elapsed > 0 else { return }
        let tokens = Double(reply.count) / 4
        if tokens > 0 { lastTokensPerSecond = tokens / elapsed }
    }

    /// Write a CGImage to a temporary JPEG and return its path (LiteRT-LM takes an
    /// image *file*, while ORB captures a CGImage). Caller deletes it.
    private static func writeTempImage(_ image: CGImage) -> String? {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("orb-shot-\(UUID().uuidString).jpg")
        do { try data.write(to: url); return url.path } catch { return nil }
    }
}
