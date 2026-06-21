//
//  SettingsView.swift
//  ORB
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var app: AppState
    @State private var showDeleteModels = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings").font(ORBTheme.ui(22, weight: .bold))

                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 18) {
                        generalCard
                        modelsCard
                        storageCard
                    }
                    VStack(spacing: 18) {
                        automationCard
                        notificationsCard
                    }
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 38).padding(.vertical, 34)
        }
    }

    // MARK: Cards

    private var generalCard: some View {
        SettingsCard(title: "GENERAL") {
            SettingsRow(label: "Global hotkey") {
                Text(settings.hotkeyDisplay).font(ORBTheme.mono(11))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: "F4F2EE")))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(ORBTheme.line))
            }
            SettingsRow(label: "Launch at login") {
                Toggle("", isOn: $settings.launchAtLogin).toggleStyle(.switch).labelsHidden().tint(ORBTheme.accent)
            }
            SettingsRow(label: "Show dock icon") {
                Toggle("", isOn: $settings.showDockIcon).toggleStyle(.switch).labelsHidden().tint(ORBTheme.accent)
            }
            SettingsRow(label: "Theme") {
                Picker("", selection: $settings.theme) {
                    ForEach(SettingsStore.Theme.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }.labelsHidden().frame(width: 110)
            }
        }
    }

    private var modelsCard: some View {
        SettingsCard(title: "MODELS") {
            SettingsRow(label: "Speech-to-text") {
                modelTag("Moonshine Base", ready: app.models.moonshine.isReady)
            }
            SettingsRow(label: "Language model") {
                modelTag("Gemma 4 E4B · 4-bit", ready: app.models.gemma.isReady)
            }
        }
    }

    private func modelTag(_ name: String, ready: Bool) -> some View {
        HStack(spacing: 8) {
            Text(name).font(ORBTheme.ui(13, weight: .medium))
            StatusPill(text: ready ? "READY" : "NOT INSTALLED", kind: ready ? .good : .neutral)
        }
    }

    private var storageCard: some View {
        SettingsCard(title: "MODEL STORAGE") {
            VStack(alignment: .leading, spacing: 10) {
                Text("All models live in one folder you can inspect, back up or relocate.")
                    .font(ORBTheme.ui(12.5)).foregroundStyle(ORBTheme.ink2)
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(ORBTheme.accent)
                    Text(app.models.modelsRoot.path)
                        .font(ORBTheme.mono(10.5)).foregroundStyle(ORBTheme.ink2)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(app.models.isUsingDefaultFolder ? "DEFAULT" : "CUSTOM")
                        .font(ORBTheme.mono(9, weight: .semibold)).foregroundStyle(ORBTheme.ink3)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(ORBTheme.board))
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "F4F2EE")))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ORBTheme.line))

                HStack(spacing: 10) {
                    Button("Change…") { chooseModelsFolder() }
                        .buttonStyle(ORBSecondaryButtonStyle())
                    if !app.models.isUsingDefaultFolder {
                        Button("Reset to default") { app.models.setModelsFolder(nil) }
                            .buttonStyle(.plain)
                            .font(ORBTheme.ui(13, weight: .semibold)).foregroundStyle(ORBTheme.accent)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)

            SettingsRow(label: "On disk") {
                Text(app.models.totalSizeLabel).font(ORBTheme.mono(11)).foregroundStyle(ORBTheme.ink2)
            }
            HStack(spacing: 10) {
                Button("Reveal in Finder") { app.models.revealModelsFolder() }
                    .buttonStyle(ORBSecondaryButtonStyle())
                Spacer()
                Button("Delete all models") { showDeleteModels = true }
                    .buttonStyle(.plain)
                    .font(ORBTheme.ui(13, weight: .semibold)).foregroundStyle(ORBTheme.danger)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .overlay(Divider(), alignment: .top)
        }
        .alert("Delete all downloaded models?", isPresented: $showDeleteModels) {
            Button("Delete", role: .destructive) { app.models.deleteAllModels() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes Moonshine and Gemma from disk. You'll need to download them again before ORB can run commands.")
        }
    }

    /// Let the user pick a new folder for model storage. Existing downloads stay
    /// where they are; future downloads go to the new location.
    private func chooseModelsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose where ORB should store its models."
        panel.directoryURL = app.models.modelsRoot
        if panel.runModal() == .OK, let url = panel.url {
            // Store models inside an "ORB Models" subfolder of the chosen directory.
            let target = url.appendingPathComponent("ORB Models", isDirectory: true)
            try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            app.models.setModelsFolder(target)
        }
    }

    private var automationCard: some View {
        SettingsCard(title: "VOICE & AUTOMATION") {
            sliderRow(label: "Silence timeout",
                      value: $settings.silenceTimeout, range: 0.5...3.0,
                      display: String(format: "%.1f s", settings.silenceTimeout))
            sliderRow(label: "Action delay between steps",
                      value: $settings.actionDelay, range: 0.2...1.0,
                      display: "\(Int(settings.actionDelay * 1000)) ms")
            SettingsRow(label: "Max retries on failure") {
                HStack(spacing: 5) {
                    ForEach([1, 2, 3], id: \.self) { n in
                        Button("\(n)") { settings.maxRetries = n }
                            .buttonStyle(.plain)
                            .font(ORBTheme.mono(11))
                            .frame(width: 22, height: 22)
                            .foregroundStyle(settings.maxRetries == n ? .white : ORBTheme.ink2)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(settings.maxRetries == n ? ORBTheme.accent : Color(hex: "F4F2EE")))
                    }
                }
            }
            SettingsRow(label: "Confirm before executing") {
                Toggle("", isOn: $settings.confirmBeforeExecuting).toggleStyle(.switch).labelsHidden().tint(ORBTheme.accent)
            }
            SettingsRow(label: "Show glow border") {
                Toggle("", isOn: $settings.showGlowBorder).toggleStyle(.switch).labelsHidden().tint(ORBTheme.accent)
            }
            SettingsRow(label: "Free model RAM when idle") {
                Toggle("", isOn: $settings.freeRAMWhenIdle).toggleStyle(.switch).labelsHidden().tint(ORBTheme.accent)
            }
        }
    }

    private var notificationsCard: some View {
        SettingsCard(title: "NOTIFICATIONS") {
            SettingsRow(label: "Speak result aloud") {
                Toggle("", isOn: $settings.speakResult).toggleStyle(.switch).labelsHidden().tint(ORBTheme.accent)
            }
            SettingsRow(label: "Banner notifications") {
                Toggle("", isOn: $settings.bannerNotifications).toggleStyle(.switch).labelsHidden().tint(ORBTheme.accent)
            }
            SettingsRow(label: "Sound on completion") {
                Toggle("", isOn: $settings.soundOnCompletion).toggleStyle(.switch).labelsHidden().tint(ORBTheme.accent)
            }
        }
    }

    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(spacing: 9) {
            HStack {
                Text(label).font(ORBTheme.ui(13))
                Spacer()
                Text(display).font(ORBTheme.mono(11)).foregroundStyle(ORBTheme.accent)
            }
            Slider(value: value, in: range).tint(ORBTheme.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - Reusable settings layout

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel(text: title).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(ORBTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ORBTheme.line))
    }
}

struct SettingsRow<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack {
            Text(label).font(ORBTheme.ui(13))
            Spacer()
            trailing
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .overlay(Divider(), alignment: .top)
    }
}
