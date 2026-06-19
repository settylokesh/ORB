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

        // Global hotkey → open popover + start listening.
        GlobalHotkeyManager.shared.onTrigger = { [weak self] in
            self?.statusBar.activateFromHotkey()
        }
        GlobalHotkeyManager.shared.register()

        NotificationManager.shared.requestAuthorization()
        LoginItem.set(appState.settings.launchAtLogin)

        if !appState.settings.hasOnboarded {
            windowManager.showOnboarding()
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
