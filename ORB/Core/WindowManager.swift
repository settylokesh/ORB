//
//  WindowManager.swift
//  ORB
//
//  Owns the main window and the onboarding window (managed in AppKit so the
//  menu-bar agent has full control over when they appear).
//

import AppKit
import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case dashboard, history, settings, permissions, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .history: return "History"
        case .settings: return "Settings"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }
}

@MainActor
final class WindowManager {
    private let appState: AppState
    private var mainWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var activationObserver: NSObjectProtocol?

    init(appState: AppState) {
        self.appState = appState
        // When the user switches back to ORB (e.g. after toggling a permission
        // in System Settings), surface whichever ORB window is open so it isn't
        // stranded behind other apps — without forcing it to float on top.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.bringFrontmostToFront() }
        }
    }

    deinit {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    /// Bring the active ORB window forward (onboarding takes priority over the
    /// main window). Called when the app is reactivated.
    private func bringFrontmostToFront() {
        if let w = onboardingWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
        } else if let w = mainWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
        }
    }

    func showMain(tab: MainTab) {
        appState.selectedTab = tab
        if mainWindow == nil {
            let host = NSHostingController(rootView: MainWindowView()
                .environmentObject(appState)
                .environmentObject(appState.settings)
                .environmentObject(appState.history)
                .environmentObject(appState.permissions))
            let window = NSWindow(contentViewController: host)
            window.title = "ORB"
            window.setContentSize(NSSize(width: 1040, height: 680))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.center()
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let host = NSHostingController(rootView:
                OnboardingView(onFinish: { [weak self] in self?.finishOnboarding() })
                    .environmentObject(appState)
                    .environmentObject(appState.settings)
                    .environmentObject(appState.history)
                    .environmentObject(appState.permissions))
            let window = NSWindow(contentViewController: host)
            window.title = "Welcome to ORB"
            window.setContentSize(NSSize(width: 720, height: 640))
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            // A normal-level window (so it does NOT stay pinned on top of other
            // apps/tabs). It must not auto-hide when ORB loses focus, otherwise
            // sending the user to System Settings would leave nothing to return
            // to; instead we re-surface it when ORB is reactivated (see
            // `bringFrontmostToFront`).
            window.hidesOnDeactivate = false
            window.center()
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func finishOnboarding() {
        appState.settings.hasOnboarded = true
        onboardingWindow?.close()
        onboardingWindow = nil
        showMain(tab: .dashboard)
    }
}
