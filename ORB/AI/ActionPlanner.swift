//
//  ActionPlanner.swift
//  ORB
//
//  Rule-based intent → action mapping. This stands in for Gemma's planning
//  output and is good enough to drive many real commands end-to-end. A real
//  LLM adapter would return the same `CommandIntent` shape from the model.
//

import Foundation

struct ActionPlanner {

    func plan(for transcript: String) -> CommandIntent {
        let text = transcript.lowercased()

        // --- Web search (Chrome / Safari / Google) ---
        if text.contains("search") && (text.contains("chrome") || text.contains("google") || text.contains("web") || text.contains("safari")) {
            let query = extractQuery(after: ["search for", "search the", "search"], in: transcript)
            let browser = text.contains("safari") ? "Safari" : "Google Chrome"
            return CommandIntent(
                summary: "Search the web for “\(query)”",
                targetApp: browser,
                actions: [
                    PlannedAction(kind: .openApp, title: "Launch \(browser)", params: ["app": browser]),
                    PlannedAction(kind: .keyShortcut, title: "Focus the address bar", params: ["combo": "cmd+l"]),
                    PlannedAction(kind: .type, title: "Type the search query", params: ["text": "https://www.google.com/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"]),
                    PlannedAction(kind: .keyShortcut, title: "Press Return & load results", params: ["combo": "return"]),
                    PlannedAction(kind: .verify, title: "Verify page loaded"),
                ])
        }

        // --- Open a URL / website ---
        if text.contains("open") && (text.contains("youtube") || text.contains(".com") || text.contains("website") || text.contains("url")) {
            let url = detectURL(in: text)
            return CommandIntent(
                summary: "Open \(url)",
                targetApp: "Browser",
                actions: [
                    PlannedAction(kind: .openURL, title: "Open \(url)", params: ["url": url]),
                    PlannedAction(kind: .verify, title: "Verify page loaded"),
                ])
        }

        // --- Volume ---
        if text.contains("volume") || text.contains("mute") {
            if text.contains("mute") {
                return CommandIntent(summary: "Mute the system", targetApp: nil,
                    actions: [PlannedAction(kind: .setVolume, title: "Mute system volume", params: ["value": "0"])])
            }
            let pct = extractPercent(in: text) ?? (text.contains("up") ? 70 : 30)
            return CommandIntent(summary: "Set volume to \(pct)%", targetApp: nil,
                actions: [PlannedAction(kind: .setVolume, title: "Set volume to \(pct)%", params: ["value": String(pct)])])
        }

        // --- Find a file ---
        if text.contains("find") && text.contains("file") || text.contains("find file") {
            let name = extractQuery(after: ["find the file", "find file", "find"], in: transcript)
                .replacingOccurrences(of: "file", with: "").trimmingCharacters(in: .whitespaces)
            return CommandIntent(
                summary: "Find file “\(name)”",
                targetApp: "Finder",
                actions: [
                    PlannedAction(kind: .findFile, title: "Search Spotlight for “\(name)”", params: ["name": name]),
                    PlannedAction(kind: .verify, title: "Open the matching file"),
                ])
        }

        // --- Screenshot ---
        if text.contains("screenshot") || text.contains("screen shot") {
            return CommandIntent(summary: "Take a screenshot", targetApp: nil,
                actions: [PlannedAction(kind: .screenshot, title: "Capture the full screen")])
        }

        // --- Generic "open <app>" ---
        if text.contains("open") || text.contains("launch") {
            let app = detectAppName(in: transcript)
            return CommandIntent(
                summary: "Open \(app)",
                targetApp: app,
                actions: [
                    PlannedAction(kind: .openApp, title: "Launch \(app)", params: ["app": app]),
                    PlannedAction(kind: .verify, title: "Verify \(app) is frontmost"),
                ])
        }

        // --- Fallback: treat as a web search ---
        return CommandIntent(
            summary: "Search the web for “\(transcript)”",
            targetApp: "Google Chrome",
            actions: [
                PlannedAction(kind: .openURL, title: "Search Google",
                              params: ["url": "https://www.google.com/search?q=\(transcript.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"]),
                PlannedAction(kind: .verify, title: "Verify page loaded"),
            ])
    }

    // MARK: - Tiny parsing helpers

    private func extractQuery(after markers: [String], in transcript: String) -> String {
        let lower = transcript.lowercased()
        for m in markers {
            if let r = lower.range(of: m) {
                let start = transcript.index(transcript.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: r.upperBound))
                return transcript[start...].trimmingCharacters(in: .whitespaces)
            }
        }
        return transcript
    }

    private func extractPercent(in text: String) -> Int? {
        let digits = text.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        if let first = digits.first, let v = Int(first) { return min(100, max(0, v)) }
        return nil
    }

    private func detectURL(in text: String) -> String {
        if text.contains("youtube") { return "https://www.youtube.com" }
        if let token = text.split(separator: " ").first(where: { $0.contains(".com") || $0.contains(".org") || $0.contains(".net") }) {
            let t = String(token)
            return t.hasPrefix("http") ? t : "https://\(t)"
        }
        return "https://www.google.com"
    }

    private func detectAppName(in transcript: String) -> String {
        let known = ["Safari", "Google Chrome", "Chrome", "Spotify", "Music", "Mail", "Notes",
                     "Reminders", "Calendar", "Finder", "WhatsApp", "Messages", "Terminal",
                     "Xcode", "Photos", "Maps", "System Settings", "Slack", "Visual Studio Code"]
        let lower = transcript.lowercased()
        for app in known where lower.contains(app.lowercased()) {
            return app == "Chrome" ? "Google Chrome" : app
        }
        // Last resort: capitalize the word after open/launch
        let parsed = extractQuery(after: ["open", "launch"], in: transcript)
        return parsed.split(separator: " ").first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Finder"
    }
}
