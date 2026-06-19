//
//  SilenceDetector.swift
//  ORB
//
//  Fires after a configurable run of below-threshold audio (default 1.5s).
//

import Foundation

final class SilenceDetector {
    var threshold: Float = 0.012        // RMS level considered "silence"
    var timeout: TimeInterval = 1.5
    var onSilence: (() -> Void)?

    private var lastLoudTime = Date()
    private var armed = false

    func start() {
        lastLoudTime = Date()
        armed = true
    }

    func stop() { armed = false }

    /// Feed the latest RMS level; call repeatedly from the audio level callback.
    func feed(level: Float) {
        guard armed else { return }
        if level > threshold {
            lastLoudTime = Date()
        } else if Date().timeIntervalSince(lastLoudTime) >= timeout {
            armed = false
            onSilence?()
        }
    }
}
