//
//  ScreenReader.swift
//  ORB
//
//  Captures the current screen so Gemma can "see" the UI. Uses
//  ScreenCaptureKit on macOS 14+, falling back to CGDisplayCreateImage on 13.
//

import Foundation
import CoreGraphics
import ScreenCaptureKit
import AppKit

@MainActor
enum ScreenReader {

    static func capture() async throws -> CGImage {
        if #available(macOS 14.0, *) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { throw ORBError.screenCaptureFailed }
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width
                config.height = display.height
                return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            } catch {
                // Fall through to the legacy path.
            }
        }
        guard let image = legacyCapture() else { throw ORBError.screenCaptureFailed }
        return image
    }

    private static func legacyCapture() -> CGImage? {
        CGDisplayCreateImage(CGMainDisplayID())
    }

    /// Saves a screenshot to the Desktop (the "take screenshot" action).
    static func saveScreenshotToDesktop() async throws -> URL {
        let image = try await capture()
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw ORBError.screenCaptureFailed }
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let url = desktop.appendingPathComponent("ORB Screenshot \(Int(Date().timeIntervalSince1970)).png")
        try data.write(to: url)
        return url
    }
}
