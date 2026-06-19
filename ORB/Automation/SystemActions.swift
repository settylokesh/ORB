//
//  SystemActions.swift
//  ORB
//
//  System-level actions that don't need on-screen clicking (volume, etc.).
//

import Foundation

enum SystemActions {

    /// Set system output volume 0...100 via AppleScript.
    static func setVolume(_ percent: Int) {
        let clamped = max(0, min(100, percent))
        runAppleScript("set volume output volume \(clamped)")
    }

    static func setMuted(_ muted: Bool) {
        runAppleScript("set volume output muted \(muted ? "true" : "false")")
    }

    @discardableResult
    static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&error)
            return error == nil
        }
        return false
    }
}
