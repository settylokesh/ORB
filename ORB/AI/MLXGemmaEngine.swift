//
//  MLXGemmaEngine.swift
//  ORB
//
//  Real vision + intent engine: Gemma 4 E4B (4-bit) running on Apple MLX.
//  Takes the transcript and a screenshot, and asks Gemma to emit a structured
//  JSON action plan. Also performs visual step verification from a screenshot.
//

import Foundation
import CoreGraphics
import CoreImage
import MLXLMCommon
import MLXVLM

@MainActor
final class MLXGemmaEngine: LLMEngine {

    let displayName = "Gemma 4 E4B"
    private(set) var isReady = false
    private(set) var ramMB = 0
    private(set) var lastTokensPerSecond: Double = 0

    private let models: ModelManager
    private let fallback = ActionPlanner()
    private var container: ModelContainer?

    init(models: ModelManager) { self.models = models }

    func load() async throws {
        guard container == nil else { isReady = true; return }
        let before = ProcessRAM.residentMB()
        container = try await models.loadGemmaContainer()
        ramMB = max(0, ProcessRAM.residentMB() - before)
        isReady = true
    }

    func unload() {
        container = nil
        isReady = false
    }

    // MARK: - Intent extraction

    func extractIntent(from transcript: String, screenshot: CGImage?) async -> CommandIntent {
        guard let container else { return fallback.plan(for: transcript) }

        let session = ChatSession(container, instructions: Self.systemPrompt)
        let prompt = "User said: \"\(transcript)\"\n\nReturn ONLY the JSON action plan."

        do {
            let start = Date()
            let reply: String
            if let cg = screenshot {
                reply = try await session.respond(to: prompt, image: .ciImage(CIImage(cgImage: cg)))
            } else {
                reply = try await session.respond(to: prompt)
            }
            let elapsed = Date().timeIntervalSince(start)
            await measureThroughput(reply, elapsed: elapsed)

            if let intent = Self.parsePlan(reply, transcript: transcript) {
                return intent
            }
        } catch {
            // fall through to the rule-based planner
        }
        return fallback.plan(for: transcript)
    }

    private func measureThroughput(_ reply: String, elapsed: TimeInterval) async {
        guard elapsed > 0, let container else { return }
        let tokens = await container.tokenizer.encode(text: reply).count
        if tokens > 0 { lastTokensPerSecond = Double(tokens) / elapsed }
    }

    // MARK: - Visual verification

    func verifyStep(_ step: PlannedAction, screenshot: CGImage?) async -> Bool {
        guard let container, let cg = screenshot else { return true }
        let session = ChatSession(container, instructions:
            "You verify UI automation. Answer with exactly YES or NO.")
        let q = "Looking at this screenshot, did this step succeed: \"\(step.title)\"? Answer YES or NO."
        do {
            let reply = try await session.respond(to: q, image: .ciImage(CIImage(cgImage: cg)))
            return reply.uppercased().contains("YES")
        } catch {
            return true   // don't block automation on a verification hiccup
        }
    }

    // MARK: - Prompt + parsing

    static let systemPrompt = """
    You are ORB, an on-device Mac automation planner. Convert the user's spoken \
    command into a JSON plan that drives macOS. Use the screenshot to ground your \
    plan in what is currently on screen.

    Respond with ONLY a JSON object, no prose, of the form:
    {
      "summary": "short human description",
      "targetApp": "App Name or null",
      "actions": [ { "kind": "<kind>", "title": "step shown to user", "params": { ... } } ]
    }

    Allowed kinds and their params:
      openApp     {"app": "Safari"}
      quitApp     {"app": "Safari"}
      openURL     {"url": "https://..."}
      type        {"text": "..."}
      keyShortcut {"combo": "cmd+l"}        // also: return, tab, cmd+shift+4
      click       {"x": "640", "y": "400"}
      scroll      {"dy": "-120"}
      findFile    {"name": "report.pdf"}
      setVolume   {"value": "0-100"}
      screenshot  {}
      wait        {}
      verify      {}
    Keep plans minimal and end browser/search flows with a "verify" step.
    """

    /// Pull the JSON object out of the model reply and decode it into a CommandIntent.
    static func parsePlan(_ reply: String, transcript: String) -> CommandIntent? {
        guard let start = reply.firstIndex(of: "{"),
              let end = reply.lastIndex(of: "}"), start < end else { return nil }
        let json = String(reply[start...end])
        guard let data = json.data(using: .utf8),
              let dto = try? JSONDecoder().decode(PlanDTO.self, from: data),
              !dto.actions.isEmpty else { return nil }

        let actions: [PlannedAction] = dto.actions.compactMap { a in
            guard let kind = ActionKind(rawValue: a.kind) else { return nil }
            return PlannedAction(kind: kind,
                                 title: a.title ?? a.kind.capitalized,
                                 params: a.params ?? [:])
        }
        guard !actions.isEmpty else { return nil }
        return CommandIntent(summary: dto.summary ?? transcript,
                             targetApp: dto.targetApp,
                             actions: actions)
    }

    private struct PlanDTO: Decodable {
        let summary: String?
        let targetApp: String?
        let actions: [ActionDTO]
    }
    private struct ActionDTO: Decodable {
        let kind: String
        let title: String?
        let params: [String: String]?
    }
}
