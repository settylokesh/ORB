//
//  StatusBarController.swift
//  ORB
//
//  The always-present menu-bar item: a state-colored icon, a click-to-open
//  popover, and a right-click dropdown menu.
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let appState: AppState
    private let windowManager: WindowManager
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState, windowManager: WindowManager) {
        self.appState = appState
        self.windowManager = windowManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 480)
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView()
                .environmentObject(appState)
                .environmentObject(appState.settings)
                .environmentObject(appState.history)
                .environmentObject(appState.permissions))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateIcon(for: appState.state)
        appState.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateIcon(for: $0) }
            .store(in: &cancellables)
    }

    // MARK: - Click handling

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Triggered by the global hotkey: open the popover and start listening.
    func activateFromHotkey() {
        if !popover.isShown { togglePopover() }
        appState.activate()
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Main Window", action: #selector(openMain), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "History", action: #selector(openHistory), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        let gemma = NSMenuItem(title: "Model: Gemma 4 E4B — \(Self.label(appState.models.gemma))", action: nil, keyEquivalent: "")
        gemma.isEnabled = false
        menu.addItem(gemma)
        let stt = NSMenuItem(title: "STT: Moonshine — \(Self.label(appState.models.moonshine))", action: nil, keyEquivalent: "")
        stt.isEnabled = false
        menu.addItem(stt)
        if !appState.models.bothReady {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Install Models…", action: #selector(openSetup), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ORB", action: #selector(quit), keyEquivalent: "q").target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // reset so left-click shows the popover again
    }

    @objc private func openMain() { windowManager.showMain(tab: .dashboard) }
    @objc private func openHistory() { windowManager.showMain(tab: .history) }
    @objc private func openSettings() { windowManager.showMain(tab: .settings) }
    @objc private func openSetup() { windowManager.showOnboarding() }
    @objc private func quit() { NSApp.terminate(nil) }

    private static func label(_ phase: ModelManager.Phase) -> String {
        switch phase {
        case .ready: return "Ready"
        case .downloading(let f): return "Downloading \(Int(f * 100))%"
        case .failed: return "Failed"
        case .notDownloaded: return "Not installed"
        }
    }

    // MARK: - Icon

    private func updateIcon(for state: AgentState) {
        guard let button = statusItem.button else { return }
        button.image = Self.icon(for: state)
        button.image?.isTemplate = false
    }

    private static func icon(for state: AgentState) -> NSImage {
        // A small branded orb (sphere + highlight) tinted by the agent state.
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(x: 2, y: 2, width: 14, height: 14)
        let sphere = NSBezierPath(ovalIn: rect)

        let base: NSColor
        switch state {
        case .idle:       base = NSColor(srgbRed: 1, green: 0.42, blue: 0.10, alpha: 1)
        case .listening:  base = NSColor(srgbRed: 1, green: 0.42, blue: 0.10, alpha: 1)
        case .planning, .executing: base = NSColor(srgbRed: 1, green: 0.55, blue: 0.18, alpha: 1)
        case .success:    base = NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1)
        case .failure:    base = NSColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1)
        }

        // Sphere body with a subtle radial sheen.
        if let gradient = NSGradient(colors: [base.blended(withFraction: 0.45, of: .white) ?? base, base]) {
            gradient.draw(in: sphere, relativeCenterPosition: NSPoint(x: -0.35, y: 0.35))
        } else {
            base.setFill(); sphere.fill()
        }
        // Specular highlight.
        NSColor(white: 1, alpha: 0.55).setFill()
        NSBezierPath(ovalIn: NSRect(x: 5, y: 9.5, width: 4, height: 3)).fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
