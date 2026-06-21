//
//  ScreenReader.swift
//  ORB
//
//  Captures the current screen so Gemma can "see" the UI. Uses
//  ScreenCaptureKit on macOS 14+, falling back to CGDisplayCreateImage on 13.
//
//  Two capture sizes:
//    • `capture()`              — full native resolution (for "save to Desktop").
//    • `capture(maxDimension:)` — downscaled for the vision model. A Retina
//      display is ~5120×2880; feeding that to Gemma's image encoder on every
//      command is the biggest per-command cost. Capturing at ≤1280px on the
//      long edge cuts the encode time and RAM dramatically with no real loss of
//      UI-grounding accuracy. ScreenCaptureKit renders straight to the smaller
//      size, so the full-res buffer is never allocated.
//

import Foundation
import CoreGraphics
import ScreenCaptureKit
import AppKit

@MainActor
enum ScreenReader {

    /// Default long-edge size handed to the vision model.
    static let modelMaxDimension = 1280

    /// Capture the main display. Pass `maxDimension` to downscale the longest
    /// edge to that many pixels (aspect preserved, never upscaled); `nil` keeps
    /// the native resolution.
    static func capture(maxDimension: Int? = nil) async throws -> CGImage {
        if #available(macOS 14.0, *) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { throw ORBError.screenCaptureFailed }
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                let (w, h) = scaledSize(width: display.width, height: display.height, max: maxDimension)
                config.width = w
                config.height = h
                return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            } catch {
                // Fall through to the legacy path.
            }
        }
        guard let image = legacyCapture() else { throw ORBError.screenCaptureFailed }
        if let maxDimension { return downscale(image, max: maxDimension) ?? image }
        return image
    }

    /// Convenience: a screenshot sized for the on-device vision model.
    static func captureForModel() async throws -> CGImage {
        try await capture(maxDimension: modelMaxDimension)
    }

    private static func legacyCapture() -> CGImage? {
        CGDisplayCreateImage(CGMainDisplayID())
    }

    /// Compute an output size whose longest edge is ≤ `max` (downscale only).
    private static func scaledSize(width: Int, height: Int, max: Int?) -> (Int, Int) {
        guard let max, max > 0 else { return (width, height) }
        let longest = Swift.max(width, height)
        guard longest > max else { return (width, height) }
        let scale = Double(max) / Double(longest)
        return (Int((Double(width) * scale).rounded()), Int((Double(height) * scale).rounded()))
    }

    /// Redraw a CGImage at a reduced size (legacy-capture path only).
    private static func downscale(_ image: CGImage, max: Int) -> CGImage? {
        let (w, h) = scaledSize(width: image.width, height: image.height, max: max)
        guard w != image.width || h != image.height else { return image }
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Saves a screenshot to the Desktop (the "take screenshot" action). Uses the
    /// full native resolution — this one is for the user, not the model.
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
