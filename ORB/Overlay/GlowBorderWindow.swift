//
//  GlowBorderWindow.swift
//  ORB
//
//  A borderless, transparent, click-through full-screen window that sits above
//  everything (including full-screen apps) and shows only the glowing edge.
//

import AppKit
import SwiftUI

final class GlowBorderWindow: NSWindow {
    init(screen: NSScreen, model: GlowModel) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: true)

        let host = NSHostingView(rootView: GlowBorderView(model: model))
        host.frame = NSRect(origin: .zero, size: screen.frame.size)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Concrete controller — owns one overlay window per screen and updates them.
@MainActor
final class GlowBorderController: GlowBorderControlling {
    private let model = GlowModel()
    private var windows: [GlowBorderWindow] = []

    private func ensureWindows() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let w = GlowBorderWindow(screen: screen, model: model)
            windows.append(w)
        }
    }

    func set(_ mode: GlowMode) {
        if mode == .hidden {
            model.mode = .hidden
            windows.forEach { $0.orderOut(nil) }
            return
        }
        ensureWindows()
        model.mode = mode
        windows.forEach { $0.orderFrontRegardless() }
    }
}
