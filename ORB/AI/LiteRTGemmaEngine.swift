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
//  The LiteRT-LM Swift package (https://github.com/google-ai-edge/LiteRT-LM) is
//  an optional dependency: everything that touches it is gated behind
//  `#if canImport(LiteRTLM)`, so the app keeps building (and the `.litertlm` keeps
//  downloading) before the package is added in Xcode. Until then this engine is an
//  inert stub that asks the user to add the package. Once the package resolves,
//  selecting "Gemma 4 E2B" runs everything through LiteRT-LM.
//
//  NOTE: the LiteRT-LM Swift API is an early preview; the exact initializer labels
//  / method names below mirror the published Swift guide and may need a small
//  adjustment when first compiled against the resolved package.
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
        // GPU (Metal) for the language model, CPU for the vision encoder — the
        // configuration LiteRT-LM recommends for Apple silicon.
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
