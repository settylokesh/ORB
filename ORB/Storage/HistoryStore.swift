//
//  HistoryStore.swift
//  ORB
//
//  Persists command history to JSON in Application Support and exposes it
//  to both the popover and the main window (one shared live store).
//

import Foundation
import Combine

final class HistoryStore: ObservableObject {
    @Published private(set) var records: [CommandRecord] = []

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ORB", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
        if records.isEmpty { seedSampleData() }
    }

    func add(_ record: CommandRecord) {
        records.insert(record, at: 0)
        persist()
    }

    func clear() {
        records.removeAll()
        persist()
    }

    /// Plain-text export of the full history.
    func exportText() -> String {
        records.map { r in
            let status = r.result == .success ? "OK" : "FAILED"
            var line = "[\(status)] \(r.transcript)  (\(r.duration.secondsLabel), \(r.retries) retries) — \(r.date.formatted())"
            if let reason = r.failureReason { line += "\n    reason: \(reason)" }
            line += "\n    steps: " + r.steps.joined(separator: " · ")
            return line
        }.joined(separator: "\n\n")
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CommandRecord].self, from: data) else { return }
        records = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func seedSampleData() {
        records = [
            CommandRecord(transcript: "Send a WhatsApp to Mom that I’m running late",
                          result: .success,
                          steps: ["Open WhatsApp", "Find contact", "Type", "Send"],
                          duration: 5.1, retries: 0, date: Date().addingTimeInterval(-120)),
            CommandRecord(transcript: "Open Chrome and search the latest M4 MacBook reviews",
                          result: .success,
                          steps: ["Launch Chrome", "Focus URL", "Type", "Return", "Verify"],
                          duration: 4.2, retries: 0, date: Date().addingTimeInterval(-720)),
            CommandRecord(transcript: "Set volume to 30%",
                          result: .success, steps: ["System volume"],
                          duration: 1.2, retries: 0, date: Date().addingTimeInterval(-1080)),
            CommandRecord(transcript: "Open Spotify and play Discover Weekly",
                          result: .success, steps: ["Launch Spotify", "Search", "Play"],
                          duration: 4.0, retries: 0, date: Date().addingTimeInterval(-10800)),
            CommandRecord(transcript: "Create reminder to buy groceries at 6pm",
                          result: .failure, steps: ["Open Reminders", "Create"],
                          duration: 30, retries: 2, date: Date().addingTimeInterval(-90000),
                          failureReason: "Timed out after 30s · Reminders did not respond"),
        ]
        persist()
    }
}
