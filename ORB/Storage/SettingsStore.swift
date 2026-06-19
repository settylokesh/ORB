//
//  SettingsStore.swift
//  ORB
//
//  User preferences, persisted in UserDefaults and observable by the UI.
//

import Foundation
import Combine
import AppKit

final class SettingsStore: ObservableObject {
    enum Theme: String, CaseIterable, Identifiable { case system, light, dark; var id: String { rawValue } }

    // General
    @Published var hotkeyDisplay: String { didSet { save(\.hotkeyDisplay, "hotkeyDisplay") } }
    @Published var launchAtLogin: Bool { didSet { save(\.launchAtLogin, "launchAtLogin"); LoginItem.set(launchAtLogin) } }
    @Published var showDockIcon: Bool { didSet { save(\.showDockIcon, "showDockIcon"); applyDockIcon() } }
    @Published var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }

    // Models
    @Published var sttModel: String { didSet { defaults.set(sttModel, forKey: "sttModel") } }
    @Published var llmModel: String { didSet { defaults.set(llmModel, forKey: "llmModel") } }

    // Voice & automation
    @Published var silenceTimeout: Double { didSet { save(\.silenceTimeout, "silenceTimeout") } }   // seconds
    @Published var actionDelay: Double { didSet { save(\.actionDelay, "actionDelay") } }             // seconds
    @Published var maxRetries: Int { didSet { save(\.maxRetries, "maxRetries") } }
    @Published var confirmBeforeExecuting: Bool { didSet { save(\.confirmBeforeExecuting, "confirmBeforeExecuting") } }
    @Published var showGlowBorder: Bool { didSet { save(\.showGlowBorder, "showGlowBorder") } }

    // Notifications
    @Published var speakResult: Bool { didSet { save(\.speakResult, "speakResult") } }
    @Published var bannerNotifications: Bool { didSet { save(\.bannerNotifications, "bannerNotifications") } }
    @Published var soundOnCompletion: Bool { didSet { save(\.soundOnCompletion, "soundOnCompletion") } }

    // Onboarding flag
    @Published var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: "hasOnboarded") } }

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        hotkeyDisplay         = d.string(forKey: "hotkeyDisplay") ?? "⌘ Space"
        launchAtLogin         = d.object(forKey: "launchAtLogin") as? Bool ?? true
        showDockIcon          = d.object(forKey: "showDockIcon") as? Bool ?? true
        theme                 = Theme(rawValue: d.string(forKey: "theme") ?? "system") ?? .system
        sttModel              = d.string(forKey: "sttModel") ?? "Moonshine Small"
        llmModel              = d.string(forKey: "llmModel") ?? "Gemma 4 E4B"
        silenceTimeout        = d.object(forKey: "silenceTimeout") as? Double ?? 1.5
        actionDelay           = d.object(forKey: "actionDelay") as? Double ?? 0.4
        maxRetries            = d.object(forKey: "maxRetries") as? Int ?? 2
        confirmBeforeExecuting = d.object(forKey: "confirmBeforeExecuting") as? Bool ?? false
        showGlowBorder        = d.object(forKey: "showGlowBorder") as? Bool ?? true
        speakResult           = d.object(forKey: "speakResult") as? Bool ?? false
        bannerNotifications   = d.object(forKey: "bannerNotifications") as? Bool ?? true
        soundOnCompletion     = d.object(forKey: "soundOnCompletion") as? Bool ?? true
        hasOnboarded          = d.bool(forKey: "hasOnboarded")
    }

    private func save<T>(_ keyPath: KeyPath<SettingsStore, T>, _ key: String) {
        defaults.set(self[keyPath: keyPath], forKey: key)
    }

    func applyDockIcon() {
        NSApplication.shared.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }
}
