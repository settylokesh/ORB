//
//  AppModels.swift
//  ORB
//
//  Core value types shared across the voice → intent → action pipeline.
//

import Foundation

/// The single source of truth for the agent lifecycle.
/// Drives the menu-bar icon, popover state, and glow border.
enum AgentState: Equatable {
    case idle
    case listening
    case planning      // STT done, Gemma extracting intent
    case executing     // running action steps
    case success
    case failure
}

/// One planned action step shown in the executing list.
struct ActionStep: Identifiable, Equatable, Codable {
    enum Status: String, Codable { case pending, running, done, failed }
    var id = UUID()
    var title: String
    var status: Status = .pending
}

/// The kinds of atomic actions the executor knows how to run.
enum ActionKind: String, Codable, CaseIterable {
    case openApp
    case quitApp
    case click
    case type
    case keyShortcut
    case scroll
    case findFile
    case openURL
    case setVolume
    case screenshot
    case wait
    case verify
}

/// A concrete, executable instruction produced by the planner.
struct PlannedAction: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: ActionKind
    var title: String
    /// Free-form parameters (app name, text, url, key combo, coordinate…).
    var params: [String: String] = [:]
}

/// The structured intent Gemma extracts from the transcript.
struct CommandIntent: Codable, Equatable {
    var summary: String
    var targetApp: String?
    var actions: [PlannedAction]
}

/// A persisted record of a completed (or failed) command.
struct CommandRecord: Identifiable, Codable, Equatable {
    enum Result: String, Codable { case success, failure }
    var id = UUID()
    var transcript: String
    var result: Result
    var steps: [String]          // human-readable step titles
    var duration: TimeInterval
    var retries: Int
    var date: Date
    var failureReason: String?
}

/// Readiness of a local model.
struct ModelStatus: Equatable {
    var name: String
    var subtitle: String
    var isReady: Bool
    var ramMB: Int
    /// e.g. "81 tok/s" or "107 ms"
    var metric: String
    var metricLabel: String
}

/// Errors surfaced from the pipeline with user-facing copy.
enum ORBError: LocalizedError, Equatable {
    case microphoneDenied
    case accessibilityMissing
    case screenRecordingMissing
    case modelNotDownloaded(String)
    case runtimeUnavailable(String)
    case appNotFound(String)
    case fileNotFound(String)
    case actionFailed(String)
    case timeout
    case screenCaptureFailed
    case lowMemory

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:        return "Microphone access is off. Enable it to give voice commands."
        case .accessibilityMissing:    return "Accessibility permission is required to control your Mac."
        case .screenRecordingMissing:  return "Screen Recording is required so ORB can see the UI."
        case .modelNotDownloaded(let m): return "\(m) isn't downloaded yet."
        case .runtimeUnavailable(let m): return m
        case .appNotFound(let a):      return "“\(a)” isn't installed on this Mac."
        case .fileNotFound(let f):     return "No file matches “\(f)”."
        case .actionFailed(let s):     return "Action failed: \(s)"
        case .timeout:                 return "The command timed out after 30 seconds."
        case .screenCaptureFailed:     return "Couldn't capture the screen. Try again."
        case .lowMemory:               return "Low memory — close some apps and try again."
        }
    }
}
