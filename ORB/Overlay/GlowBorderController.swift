//
//  GlowBorderController.swift
//  ORB
//
//  Abstraction the orchestrator uses to drive the full-screen glow overlay,
//  so AppState doesn't need to know about NSWindow. The concrete
//  implementation lives in GlowBorderWindow.swift.
//

import Foundation

/// Visual modes for the screen-edge glow.
enum GlowMode: Equatable {
    case hidden
    case planning      // dim slow pulse
    case executing     // bright fast pulse
    case success       // flash green once
    case failure       // flash red once
}

@MainActor
protocol GlowBorderControlling: AnyObject {
    func set(_ mode: GlowMode)
}
