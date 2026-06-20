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

    init(appState: AppState) { self.appState = appState }

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
            // Onboarding walks the user through System Settings to grant
            // permissions. Float above other apps (incl. System Settings) and
            // follow the active Space so the instructions never get buried —
            // otherwise opening Settings sends ORB to the back and the user has
            // to hunt for the menu-bar icon to bring it forward again.
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
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
