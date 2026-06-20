//
//  ActionExecutor.swift
//  ORB
//
//  Runs a list of planned actions using the real automation primitives,
//  verifying each step with Gemma and retrying on failure.
//

import Foundation
import CoreGraphics
import ApplicationServices

@MainActor
final class ActionExecutor {
    var actionDelay: TimeInterval = 0.4
    var maxRetries: Int = 2

    private let llm: LLMEngine
    private let fileSearch = FileSearchEngine()

    /// Reports (stepIndex, newStatus) so the UI can update live.
    var onStepStatus: ((Int, ActionStep.Status) -> Void)?
    /// Total retries used across the run.
    private(set) var retriesUsed = 0

    var isCancelled = false

    init(llm: LLMEngine) { self.llm = llm }

    /// Executes all actions in order. Throws on unrecoverable failure.
    func execute(_ actions: [PlannedAction]) async throws {
        retriesUsed = 0
        for (i, action) in actions.enumerated() {
            if isCancelled { throw CancellationError() }
            onStepStatus?(i, .running)

            var attempt = 0
            var succeeded = false
            while attempt <= maxRetries {
                if isCancelled { throw CancellationError() }
                do {
                    try await perform(action)
                    // Only explicit `verify` steps pay for a Gemma vision check;
                    // other actions succeed if they ran without throwing. (Verifying
                    // every step is too slow and can spuriously fail real commands.)
                    if action.kind == .verify {
                        let shot = try? await ScreenReader.capture()
                        if await llm.verifyStep(action, screenshot: shot) { succeeded = true; break }
                    } else {
                        succeeded = true; break
                    }
                } catch let e as ORBError {
                    // Non-retryable hard errors bubble up immediately.
                    switch e {
                    case .appNotFound, .fileNotFound, .accessibilityMissing: throw e
                    default: break
                    }
                } catch {
                    // retry
                }
                attempt += 1
                if attempt <= maxRetries { retriesUsed += 1 }
                try? await Task.sleep(nanoseconds: UInt64(actionDelay * 1_000_000_000))
            }

            guard succeeded else {
                onStepStatus?(i, .failed)
                throw ORBError.actionFailed(action.title)
            }
            onStepStatus?(i, .done)
            try? await Task.sleep(nanoseconds: UInt64(actionDelay * 1_000_000_000))
        }
    }

    // MARK: - Performing one action

    /// Actions that drive the keyboard/mouse via CGEvent need Accessibility.
    private static func requiresAccessibility(_ kind: ActionKind) -> Bool {
        switch kind {
        case .type, .keyShortcut, .click, .scroll: return true
        default: return false
        }
    }

    private func perform(_ action: PlannedAction) async throws {
        // Input-control actions silently no-op without Accessibility, which looks
        // like the agent "did nothing". Fail loudly instead so the user can grant it.
        if Self.requiresAccessibility(action.kind), !AXIsProcessTrusted() {
            throw ORBError.accessibilityMissing
        }
        switch action.kind {
        case .openApp:
            try await AppLauncher.open(action.params["app"] ?? "")
        case .quitApp:
            AppLauncher.quit(action.params["app"] ?? "")
        case .openURL:
            AppLauncher.openURL(action.params["url"] ?? "")
        case .type:
            KeyboardController.type(action.params["text"] ?? "")
        case .keyShortcut:
            KeyboardController.pressCombo(action.params["combo"] ?? "")
        case .click:
            if let x = Double(action.params["x"] ?? ""), let y = Double(action.params["y"] ?? "") {
                MouseController.click(at: CGPoint(x: x, y: y))
            }
        case .scroll:
            MouseController.scroll(dy: Int32(action.params["dy"] ?? "-120") ?? -120)
        case .setVolume:
            if let v = Int(action.params["value"] ?? "") { SystemActions.setVolume(v) }
        case .findFile:
            let results = await fileSearch.search(name: action.params["name"] ?? "")
            guard let first = results.first else { throw ORBError.fileNotFound(action.params["name"] ?? "") }
            AppLauncher.openURL(first.absoluteString)
        case .screenshot:
            _ = try await ScreenReader.saveScreenshotToDesktop()
        case .wait:
            try? await Task.sleep(nanoseconds: 400_000_000)
        case .verify:
            break // verification happens in the run loop
        }
    }
}
