//
//  PermissionsManager.swift
//  ORB
//
//  Tracks the three permissions ORB needs and helps the user grant them.
//

import Foundation
import Combine
import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class PermissionsManager: ObservableObject {
    enum Status: Equatable { case granted, denied, notDetermined }

    @Published var microphone: Status = .notDetermined
    @Published var accessibility: Status = .notDetermined
    @Published var screenRecording: Status = .notDetermined

    var allGranted: Bool {
        microphone == .granted && accessibility == .granted && screenRecording == .granted
    }

    init() { refresh() }

    func refresh() {
        // Microphone
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphone = .granted
        case .denied, .restricted: microphone = .denied
        default: microphone = .notDetermined
        }
        // Accessibility
        accessibility = AXIsProcessTrusted() ? .granted : .denied
        // Screen recording
        screenRecording = CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphone = granted ? .granted : .denied
    }

    func requestAccessibility() {
        // Prompts the system dialog and opens the relevant settings pane.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        openSettings(.accessibility)
    }

    func requestScreenRecording() {
        // Triggers the system prompt the first time; afterwards opens settings.
        if !CGRequestScreenCaptureAccess() {
            openSettings(.screenRecording)
        }
        refresh()
    }

    enum Pane: String {
        case accessibility = "Privacy_Accessibility"
        case screenRecording = "Privacy_ScreenCapture"
        case microphone = "Privacy_Microphone"
    }

    func openSettings(_ pane: Pane) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)")!
        NSWorkspace.shared.open(url)
    }
}
