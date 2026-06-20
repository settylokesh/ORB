//
//  PermissionsManager.swift
//  ORB
//
//  Tracks the three permissions ORB needs and helps the user grant them.
//
//  macOS caches some permission checks for the lifetime of the process, which
//  is why a freshly-granted permission can keep showing "Needed" until the app
//  is relaunched. To avoid that we (a) detect Screen Recording live by reading
//  other apps' window names instead of the cached preflight, and (b) poll on a
//  timer so a grant made in System Settings is reflected without a restart.
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

    private var pollTimer: Timer?

    init() {
        refresh()
        startMonitoring()
    }

    deinit { pollTimer?.invalidate() }

    /// Poll the live permission state so grants made while ORB is running are
    /// picked up automatically (no need to click Refresh or relaunch).
    func startMonitoring() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refresh() {
        // Microphone
        let mic: Status
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: mic = .granted
        case .denied, .restricted: mic = .denied
        default: mic = .notDetermined
        }
        // Accessibility — AXIsProcessTrusted reads live TCC state every call.
        let ax: Status = AXIsProcessTrusted() ? .granted : .denied
        // Screen recording — live check (preflight alone is cached per-process).
        let screen: Status = hasScreenRecordingPermission() ? .granted : .denied

        // Only assign when something actually changed to avoid needless UI churn.
        if microphone != mic { microphone = mic }
        if accessibility != ax { accessibility = ax }
        if screenRecording != screen { screenRecording = screen }
    }

    /// Live Screen Recording check.
    ///
    /// `CGPreflightScreenCaptureAccess()` caches its answer for the life of the
    /// process, so after the user grants access it keeps returning `false` until
    /// relaunch. Reading window metadata reflects the *current* grant: without
    /// permission macOS omits `kCGWindowName` for windows we don't own, so if we
    /// can read another process's window name, access is live.
    private func hasScreenRecordingPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let ourPID = NSRunningApplication.current.processIdentifier
        for info in infoList {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ourPID else { continue }
            if let name = info[kCGWindowName as String] as? String, !name.isEmpty {
                return true
            }
        }
        return false
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

    /// Relaunch ORB. macOS sometimes only re-reads a freshly granted permission
    /// (or a re-signed dev build's TCC entry) after a restart — this gives the
    /// user a one-click way to do that.
    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.4; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
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
