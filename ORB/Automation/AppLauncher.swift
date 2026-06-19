//
//  AppLauncher.swift
//  ORB
//
//  Launching, quitting and switching apps via NSWorkspace.
//

import Foundation
import AppKit

enum AppLauncher {

    static func url(for appName: String) -> URL? {
        let ws = NSWorkspace.shared
        if let path = ws.fullPath(forApplication: appName) {
            return URL(fileURLWithPath: path)
        }
        // Fallback: scan common Applications directories.
        let dirs = ["/Applications", "/System/Applications",
                    NSHomeDirectory() + "/Applications"]
        for dir in dirs {
            let candidate = "\(dir)/\(appName).app"
            if FileManager.default.fileExists(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    @discardableResult
    static func open(_ appName: String) async throws -> Bool {
        guard let appURL = url(for: appName) else { throw ORBError.appNotFound(appName) }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        return true
    }

    static func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    static func quit(_ appName: String) {
        for app in NSWorkspace.shared.runningApplications where app.localizedName == appName {
            app.terminate()
        }
    }
}
