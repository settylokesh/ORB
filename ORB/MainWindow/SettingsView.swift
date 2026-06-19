//
//  SettingsView.swift
//  ORB
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings").font(ORBTheme.ui(22, weight: .bold))

                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 18) {
                        generalCard
                        modelsCard
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
                Picker("", selection: $settings.sttModel) {
                    ForEach(["Moonshine Tiny", "Moonshine Small", "Moonshine Medium"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 170)
            }
            SettingsRow(label: "Language model") {
                Picker("", selection: $settings.llmModel) {
                    ForEach(["Gemma 4 E2B", "Gemma 4 E4B", "Gemma 4 26B MoE"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 170)
            }
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
