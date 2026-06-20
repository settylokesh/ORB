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
    }

    func add(_ record: CommandRecord) {
        records.insert(record, at: 0)
        persist()
    }

    /// Delete a single record (per-row delete in the UI).
    func delete(_ record: CommandRecord) {
        records.removeAll { $0.id == record.id }
        persist()
    }

    /// Delete records at the given list offsets (swipe / multi-delete).
    func delete(at offsets: IndexSet) {
        records = records.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map { $0.element }
        persist()
    }

    /// Clear the entire history.
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
}
