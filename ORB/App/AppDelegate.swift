//
//  AppDelegate.swift
//  ORB
//
//  Wires together the menu-bar item, global hotkey, glow overlay and windows.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private let glow = GlowBorderController()
    private var statusBar: StatusBarController!
    private var windowManager: WindowManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.glow = glow
        appState.settings.applyDockIcon()

        windowManager = WindowManager(appState: appState)
        statusBar = StatusBarController(appState: appState, windowManager: windowManager)

        // Let AppState drive window navigation (e.g. "Finish setup" from the popover).
        appState.onShowMain = { [weak self] tab in self?.windowManager.showMain(tab: tab) }
        appState.onShowOnboarding = { [weak self] in self?.windowManager.showOnboarding() }

        // Global hotkey → open popover + start listening.
        GlobalHotkeyManager.shared.onTrigger = { [weak self] in
            self?.statusBar.activateFromHotkey()
        }
        GlobalHotkeyManager.shared.register()

        NotificationManager.shared.requestAuthorization()
        LoginItem.set(appState.settings.launchAtLogin)

        // Reconcile state with what's actually on disk / granted before deciding.
        appState.models.refresh()
        appState.permissions.refresh()

        // Show the setup flow on first run, or whenever the models the app needs
        // aren't actually installed yet — so the user is never dropped into a
        // dashboard that silently can't do anything.
        if !appState.settings.hasOnboarded || !appState.models.bothReady {
            windowManager.showOnboarding()
        } else {
            windowManager.showMain(tab: .dashboard)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowManager.showMain(tab: .dashboard)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkeyManager.shared.unregister()
    }
}
