//
//  LoginItem.swift
//  ORB
//
//  Launch-at-login via ServiceManagement (macOS 13+).
//

import Foundation
import ServiceManagement

enum LoginItem {
    static func set(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("ORB: login item update failed: \(error.localizedDescription)")
        }
    }
}
