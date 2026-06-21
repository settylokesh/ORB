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
    let models = ModelManager()

    // Real on-device engines (Moonshine via ONNX, Gemma 4 E4B via MLX).
    let stt: STTEngine
    let llm: LLMEngine
    private let audio = AudioCaptureEngine()
    private lazy var executor = ActionExecutor(llm: llm)

    private var cancellables = Set<AnyCancellable>()

    init() {
        stt = MoonshineSTT(models: models)
        llm = MLXGemmaEngine(models: models)
        // Re-publish when the model manager changes so download progress is live.
        models.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Set by AppDelegate once the overlay window exists.
    weak var glow: GlowBorderControlling?

    /// Window navigation, injected by AppDelegate (which owns the WindowManager).
    var onShowMain: ((MainTab) -> Void)?
    var onShowOnboarding: (() -> Void)?

    /// Open the setup/onboarding flow so the user can install models & permissions.
    func openSetup() { onShowOnboarding?() }

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
    /// True while the heavy Gemma container is loading into memory (warm-up or the
    /// first command). Lets the UI say "Loading model" instead of "Planning…".
    @Published var isLoadingModel = false

    private var runStart = Date()
    private var runTask: Task<Void, Never>?
    private var idleUnloadTask: Task<Void, Never>?
    private var lastTranscript = ""

    /// How long ORB stays idle before it frees the resident Gemma container.
    private let idleUnloadDelay: UInt64 = 180_000_000_000   // 3 minutes

    var isBusy: Bool { state != .idle && state != .success && state != .failure }

    // MARK: - Model status (for dashboard / idle pills)

    var gemmaStatus: ModelStatus {
        ModelStatus(name: "Gemma 4 E4B", subtitle: "VISION + INTENT · MLX",
                    isReady: models.gemma.isReady, ramMB: llm.ramMB,
                    metric: llm.lastTokensPerSecond > 0 ? String(format: "%.0f", llm.lastTokensPerSecond) : "—",
                    metricLabel: "tok/s")
    }
    var moonshineStatus: ModelStatus {
        ModelStatus(name: "Moonshine Base", subtitle: "SPEECH-TO-TEXT · ONNX",
                    isReady: models.moonshine.isReady, ramMB: stt.ramMB,
                    metric: stt.lastLatencyMS > 0 ? "\(stt.lastLatencyMS)" : "—",
                    metricLabel: "ms")
    }

    // MARK: - Warm-up & idle memory management

    /// Preload the models the moment the user shows intent to use ORB (opens the
    /// popover, focuses the command field, or starts listening) so the heavy
    /// ~4 GB Gemma container is resident by the time a command actually arrives —
    /// instead of being loaded inline on the first command with no feedback.
    /// Idempotent and cheap; safe to call on every interaction.
    func warmUpForUse() {
        cancelIdleUnload()
        if models.gemma.isReady, !llm.isReady, !llm.isLoading {
            isLoadingModel = true
            Task { [weak self] in
                guard let self else { return }
                await self.llm.warmUp()
                self.isLoadingModel = false
                // Re-arm reclaim in case the user warmed ORB but ran nothing.
                self.armIdleUnload()
            }
        } else {
            // Already resident (or nothing to warm): keep idle reclaim armed so a
            // glance at the popover doesn't pin the model in memory forever.
            armIdleUnload()
        }
        if models.moonshine.isReady, !stt.isReady {
            Task { [weak self] in try? await self?.stt.load() }
        }
    }

    /// After a spell of inactivity, drop the resident models to reclaim memory
    /// (controlled by the "Free model RAM when idle" setting). The next warm-up
    /// brings them straight back, so this is invisible in normal use.
    private func armIdleUnload() {
        cancelIdleUnload()
        guard settings.freeRAMWhenIdle else { return }
        idleUnloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.idleUnloadDelay ?? 180_000_000_000)
            guard let self, !Task.isCancelled else { return }
            // Only unload if we're genuinely sitting idle (not mid-command).
            switch self.state {
            case .idle, .success, .failure:
                self.llm.unload()
                self.stt.unload()
                self.ram.setPhase(.idle)
            default:
                break
            }
        }
    }

    private func cancelIdleUnload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
    }

    /// Whether a command plausibly needs to *see* the screen to be planned well.
    /// Commands that map to direct, non-visual actions (open/quit an app, set the
    /// volume, take a screenshot, find a file, run a search) are planned text-only,
    /// which skips the costly vision encode entirely. Anything that references the
    /// screen ("click", "this", "the button") still gets a screenshot, and we
    /// default to grounding when the intent is ambiguous.
    private func visionNeeded(for transcript: String) -> Bool {
        let t = transcript.lowercased()
        let visualCues = ["click", "tap", "press the", "scroll", "button", "this ", "that ",
                          " here", "on screen", "on the screen", "what's on", "whats on",
                          "read the", "select ", "highlight", "drag"]
        if visualCues.contains(where: t.contains) { return true }
        let nonVisual = ["open ", "launch ", "quit ", "close ", "volume", "mute", "unmute",
                         "screenshot", "screen shot", "find ", "search ", "play ", "pause", "go to "]
        if nonVisual.contains(where: t.contains) { return false }
        return true   // unsure → ground the plan in a screenshot
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
        guard models.moonshine.isReady else {
            errorMessage = ORBError.modelNotDownloaded("Moonshine").errorDescription
            openSetup()   // send the user to finish installing the model
            return
        }
        guard permissions.microphone == .granted else {
            // Not yet determined → ask now; denied was handled above.
            Task { await permissions.requestMicrophone() }
            errorMessage = ORBError.microphoneDenied.errorDescription
            return
        }
        errorMessage = nil
        transcript = ""
        steps = []
        state = .listening
        ram.setPhase(.listening)

        // Warm both models now, in the background, while the user is still
        // speaking — Gemma is usually resident by the time the transcript lands.
        warmUpForUse()
        stt.beginStreaming { [weak self] partial in
            self?.transcript = partial
        }
        audio.silence.timeout = settings.silenceTimeout
        audio.onLevel = { [weak self] level in self?.audioLevel = level }
        audio.onChunk = { [weak self] chunk in self?.stt.feed(chunk) }
        audio.silence.onSilence = { [weak self] in self?.finalizeListening() }
        do {
            try audio.start()
        } catch {
            errorMessage = "Couldn't start the microphone. Check the mic permission and try again."
            state = .idle
            ram.setPhase(.idle)
            return
        }

        // Safety cap: stop after a maximum utterance length so a stuck capture
        // never hangs the agent. Real silence detection normally fires first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.state == .listening else { return }
            self.finalizeListening()
        }
    }

    func finalizeListening() {
        guard state == .listening else { return }
        state = .planning            // claim the transition so re-entry bails
        audio.stop()
        audio.onLevel = nil
        Task { [weak self] in
            guard let self else { return }
            let finalText = await self.stt.finishStreaming()
            self.transcript = finalText
            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.errorMessage = "Didn't catch that — try again."
                self.state = .idle
                self.ram.setPhase(.idle)
                return
            }
            self.runPipeline(transcript: finalText)
        }
    }

    func cancel() {
        runTask?.cancel()
        executor.isCancelled = true
        audio.stop()
        glow?.set(.hidden)
        ram.setPhase(.idle)
        isLoadingModel = false
        state = .idle
        steps = []
        armIdleUnload()
    }

    func repeatLast() {
        guard let last = lastRecord else { return }
        runPipeline(transcript: last.transcript)
    }

    // MARK: - Text input

    /// Normalizes raw typed input into a runnable command, or `nil` when there's
    /// nothing actionable. Trims the ends and collapses any internal whitespace
    /// runs (spaces, tabs, newlines) to single spaces so "  open   safari\n"
    /// becomes "open safari". Single pass over the input — O(n) in its length.
    static func normalizedCommand(_ raw: String) -> String? {
        let command = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return command.isEmpty ? nil : command
    }

    /// Run a typed command through the same plan → execute pipeline as voice,
    /// skipping speech capture entirely. Only Gemma is required (Moonshine and
    /// the microphone aren't), so a user can drive ORB with no mic permission.
    func submitTextCommand(_ raw: String) {
        // Ignore submissions while a command is already mid-flight; allow them
        // from idle and from the success/failure result cards (same as voice).
        guard !isBusy else { return }
        guard let command = Self.normalizedCommand(raw) else {
            errorMessage = "Type a command first."
            return
        }
        guard models.gemma.isReady else {
            errorMessage = ORBError.modelNotDownloaded("Gemma 4 E4B").errorDescription
            openSetup()   // send the user to finish installing the model
            return
        }
        errorMessage = nil
        transcript = command
        steps = []
        runPipeline(transcript: command)
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
        cancelIdleUnload()
        state = .planning
        ram.setPhase(.planning)
        glow?.set(settings.showGlowBorder ? .planning : .hidden)
        do {
            // Reflect a real "loading model" state when the warm-up hasn't already
            // brought Gemma resident (e.g. a typed command straight from idle).
            if !llm.isReady { isLoadingModel = true }
            try await llm.load()
            isLoadingModel = false
        } catch {
            isLoadingModel = false
            errorMessage = ORBError.modelNotDownloaded("Gemma 4 E4B").errorDescription
            state = .failure
            glow?.set(.failure)
            finishCommon()
            autoReturnToIdle()
            return
        }

        // Only pay for a (downscaled) screenshot when the command needs the model
        // to actually see the screen — most commands plan fine from text alone.
        let screenshot = visionNeeded(for: transcript)
            ? try? await ScreenReader.captureForModel()
            : nil
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
        // Keep Gemma resident between commands for responsiveness, but arm the
        // idle-unload timer so a long stretch of inactivity reclaims its memory.
        // RAM is reported live on the dashboard.
        ram.setPhase(.idle)
        armIdleUnload()
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
