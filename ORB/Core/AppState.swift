//
//  AppState.swift
//  ORB
//
//  The single shared store + orchestrator. Drives the menu-bar icon, popover,
//  main window and glow border, and runs the voice → intent → action pipeline.
//

import Foundation
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {

    // Shared sub-stores
    let settings = SettingsStore()
    let history = HistoryStore()
    let permissions = PermissionsManager()
    let ram = RAMManager()

    // Engines (behind protocols — real MLX/Moonshine adapters drop in here)
    let stt: STTEngine = SimulatedMoonshineSTT()
    let llm: LLMEngine = SimulatedGemmaEngine()
    private let audio = AudioCaptureEngine()
    private lazy var executor = ActionExecutor(llm: llm)

    /// Set by AppDelegate once the overlay window exists.
    weak var glow: GlowBorderControlling?

    // Navigation (main window tab, shared with the menu)
    @Published var selectedTab: MainTab = .dashboard

    // Live UI state
    @Published var state: AgentState = .idle
    @Published var transcript: String = ""
    @Published var audioLevel: Float = 0
    @Published var steps: [ActionStep] = []
    @Published var currentSummary: String = ""
    @Published var lastRecord: CommandRecord?
    @Published var errorMessage: String?

    private var runStart = Date()
    private var runTask: Task<Void, Never>?
    private var lastTranscript = ""

    var isBusy: Bool { state != .idle && state != .success && state != .failure }

    // MARK: - Model status (for dashboard / idle pills)

    var gemmaStatus: ModelStatus {
        ModelStatus(name: "Gemma 4 E4B", subtitle: "VISION + INTENT · MLX",
                    isReady: true, ramMB: RAMManager.gemmaMB, metric: "81", metricLabel: "tok/s")
    }
    var moonshineStatus: ModelStatus {
        ModelStatus(name: "Moonshine Small", subtitle: "SPEECH-TO-TEXT",
                    isReady: true, ramMB: RAMManager.moonshineMB, metric: "107", metricLabel: "ms")
    }

    // MARK: - Activation

    /// Toggle entry point used by the hotkey and the orb tap.
    func activate() {
        switch state {
        case .idle, .success, .failure: startListening()
        case .listening: finalizeListening()
        default: break
        }
    }

    func startListening() {
        permissions.refresh()
        guard permissions.microphone != .denied else {
            errorMessage = ORBError.microphoneDenied.errorDescription
            return
        }
        errorMessage = nil
        transcript = ""
        steps = []
        state = .listening
        ram.setPhase(.listening)

        Task { await stt.load() }
        stt.beginStreaming { [weak self] partial in
            self?.transcript = partial
        }
        audio.silence.timeout = settings.silenceTimeout
        audio.onLevel = { [weak self] level in self?.audioLevel = level }
        audio.onChunk = { [weak self] chunk in self?.stt.feed(chunk) }
        audio.silence.onSilence = { [weak self] in self?.finalizeListening() }
        try? audio.start()

        // If the mic never produces audio (e.g. no permission yet), still
        // auto-finalize so the demo flows. Real silence detection wins if it fires first.
        let timeout = settings.silenceTimeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4 + timeout) { [weak self] in
            guard let self, self.state == .listening else { return }
            self.finalizeListening()
        }
    }

    func finalizeListening() {
        guard state == .listening else { return }
        audio.stop()
        audio.onLevel = nil
        let finalText = stt.finishStreaming()
        transcript = finalText
        runPipeline(transcript: finalText)
    }

    func cancel() {
        runTask?.cancel()
        executor.isCancelled = true
        audio.stop()
        glow?.set(.hidden)
        ram.setPhase(.idle)
        state = .idle
        steps = []
    }

    func repeatLast() {
        guard let last = lastRecord else { return }
        runPipeline(transcript: last.transcript)
    }

    // MARK: - Pipeline

    private func runPipeline(transcript: String) {
        lastTranscript = transcript
        runStart = Date()
        executor.isCancelled = false
        runTask = Task { [weak self] in
            guard let self else { return }
            await self.run(transcript: transcript)
        }
    }

    private func run(transcript: String) async {
        // 1. Planning
        state = .planning
        ram.setPhase(.planning)
        glow?.set(settings.showGlowBorder ? .planning : .hidden)
        await llm.load()

        let screenshot = try? await ScreenReader.capture()
        let intent = await llm.extractIntent(from: transcript, screenshot: screenshot)
        currentSummary = intent.summary
        steps = intent.actions.map { ActionStep(title: $0.title) }

        // Optional confirmation gate.
        if settings.confirmBeforeExecuting {
            let proceed = ConfirmDialog.ask(summary: intent.summary)
            if !proceed { finishIdle(); return }
        }

        // Low-memory guard.
        if ram.isLowMemory {
            fail(reason: ORBError.lowMemory.errorDescription ?? "Low memory", intent: intent)
            return
        }

        // 2. Executing
        state = .executing
        ram.setPhase(.executing)
        glow?.set(settings.showGlowBorder ? .executing : .hidden)

        executor.actionDelay = settings.actionDelay
        executor.maxRetries = settings.maxRetries
        executor.simulateOnly = (permissions.accessibility != .granted)
        executor.onStepStatus = { [weak self] index, status in
            guard let self, self.steps.indices.contains(index) else { return }
            self.steps[index].status = status
        }

        do {
            try await withTimeout(seconds: 30) { [executor] in
                try await executor.execute(intent.actions)
            }
            succeed(intent: intent)
        } catch is CancellationError {
            finishIdle()
        } catch let e as ORBError where e == .timeout {
            fail(reason: ORBError.timeout.errorDescription ?? "Timed out", intent: intent)
        } catch {
            let reason = (error as? ORBError)?.errorDescription ?? error.localizedDescription
            fail(reason: reason, intent: intent)
        }
    }

    // MARK: - Outcomes

    private func succeed(intent: CommandIntent) {
        let duration = Date().timeIntervalSince(runStart)
        let record = CommandRecord(transcript: lastTranscript, result: .success,
                                   steps: intent.actions.map(\.title),
                                   duration: duration, retries: executor.retriesUsed, date: Date())
        lastRecord = record
        history.add(record)
        state = .success
        glow?.set(.success)
        finishCommon()
        notify(success: true, summary: intent.summary)
        autoReturnToIdle()
    }

    private func fail(reason: String, intent: CommandIntent) {
        let duration = Date().timeIntervalSince(runStart)
        let record = CommandRecord(transcript: lastTranscript, result: .failure,
                                   steps: intent.actions.map(\.title),
                                   duration: duration, retries: executor.retriesUsed, date: Date(),
                                   failureReason: reason)
        lastRecord = record
        history.add(record)
        errorMessage = reason
        state = .failure
        glow?.set(.failure)
        finishCommon()
        notify(success: false, summary: reason)
        autoReturnToIdle()
    }

    private func finishCommon() {
        llm.unload()
        ram.setPhase(.idle)
    }

    private func finishIdle() {
        finishCommon()
        glow?.set(.hidden)
        state = .idle
    }

    private func autoReturnToIdle() {
        // The glow flash lasts ~1s; hide it, but keep the result card until the
        // user dismisses it or starts a new command.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.glow?.set(.hidden)
        }
    }

    func dismissResult() {
        state = .idle
        steps = []
    }

    private func notify(success: Bool, summary: String) {
        if settings.bannerNotifications {
            NotificationManager.shared.banner(
                title: success ? "ORB · Done" : "ORB · Couldn’t finish",
                body: summary, sound: settings.soundOnCompletion)
        }
        if settings.speakResult {
            NotificationManager.shared.speak(success ? "Done. \(summary)" : "Sorry. \(summary)")
        }
    }
}

/// Races an async operation against a timeout.
func withTimeout(seconds: Double, _ operation: @escaping () async throws -> Void) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ORBError.timeout
        }
        try await group.next()
        group.cancelAll()
    }
}

/// A tiny synchronous confirm dialog (honours "Confirm before executing").
@MainActor
enum ConfirmDialog {
    static func ask(summary: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Run this command?"
        alert.informativeText = summary
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
