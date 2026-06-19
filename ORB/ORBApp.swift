//
//  ORBApp.swift
//  ORB
//
//  Menu-bar agent app. Windows are managed in AppKit via AppDelegate, so the
//  only SwiftUI scene is Settings (kept empty).
//

import SwiftUI

@main
struct ORBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
