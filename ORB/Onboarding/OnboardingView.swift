//
//  OnboardingView.swift
//  ORB
//
//  First-launch flow: welcome → mic → accessibility → screen recording →
//  model download → tutorial.
//

import SwiftUI
import Combine

struct OnboardingView: View {
    let onFinish: () -> Void
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var permissions: PermissionsManager

    @State private var step = 0
    private let total = 6

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 640)
        .background(ORBTheme.surface)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            permissions.refresh()
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: micScreen
        case 2: accessibilityScreen
        case 3: screenRecordingScreen
        case 4: downloadScreen
        default: tutorialScreen
        }
    }

    private func header(_ n: Int) -> some View {
        HStack {
            Spacer()
            MonoLabel(text: "STEP \(n) OF \(total)")
        }
        .padding(.horizontal, 30).padding(.top, 24)
    }

    // MARK: Screens

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            OrbView(size: 120)
            Text("ORB").font(ORBTheme.ui(38, weight: .bold)).tracking(5).padding(.top, 30)
            Text("Speak. Your Mac does the rest.").font(ORBTheme.ui(18, weight: .medium)).padding(.top, 10)
            Text("A local AI agent that hears your command, looks at your screen, and clicks, types and navigates for you. Nothing leaves your Mac.")
                .font(ORBTheme.ui(14)).foregroundStyle(ORBTheme.ink2)
                .multilineTextAlignment(.center).frame(width: 380).padding(.top, 14)
            Spacer()
            VStack(spacing: 14) {
                Button("Continue") { step = 1 }.buttonStyle(ORBPrimaryButtonStyle()).frame(width: 240)
                MonoLabel(text: "100% LOCAL · NO ACCOUNT · NO CLOUD")
            }
            .padding(.bottom, 46)
        }
    }

    private var micScreen: some View {
        permissionScreen(
            n: 2, icon: "mic.fill", title: "Hear your commands",
            body: "ORB needs the microphone to capture your voice. Audio is transcribed on-device by Moonshine and never recorded or uploaded.",
            status: permissions.microphone,
            primaryTitle: "Allow Microphone",
            primary: { Task { await permissions.requestMicrophone() } },
            note: "REQUIRED · macOS WILL ASK YOU TO CONFIRM")
    }

    private var accessibilityScreen: some View {
        permissionScreen(
            n: 3, icon: "cursorarrow.click.2", title: "Click, type & navigate",
            body: "Accessibility lets ORB move the cursor, click buttons and type — exactly as you would — in any app.",
            status: permissions.accessibility,
            primaryTitle: "Open Settings",
            primary: { permissions.requestAccessibility() },
            note: "ENABLES AUTOMATICALLY WHEN GRANTED",
            reset: { permissions.resetPermissions() })
    }

    private var screenRecordingScreen: some View {
        permissionScreen(
            n: 4, icon: "rectangle.inset.filled.badge.record", title: "See what you see",
            body: "Screen Recording lets Gemma read the current UI so it can find the right element and verify each action worked.",
            status: permissions.screenRecording,
            primaryTitle: "Open Settings",
            primary: { permissions.requestScreenRecording() },
            note: "FRAMES ARE PROCESSED LOCALLY, NEVER SAVED",
            reset: { permissions.resetPermissions() })
    }

    private var downloadScreen: some View {
        VStack(spacing: 0) {
            header(5)
            Spacer()
            Text("Getting the AI ready").font(ORBTheme.ui(24, weight: .semibold))
            Text("Downloaded once from Hugging Face, then runs fully offline.")
                .font(ORBTheme.ui(14)).foregroundStyle(ORBTheme.ink2).padding(.top, 10)
            VStack(spacing: 18) {
                DownloadRow(name: "Moonshine Base", subtitle: "SPEECH-TO-TEXT · ONNX",
                            phase: app.models.moonshine, bytes: app.models.moonshineBytes,
                            download: { app.models.downloadMoonshine() },
                            pause: { app.models.pauseMoonshine() },
                            resume: { app.models.resumeMoonshine() })
                // Pick which Gemma drives automation, then download it. The row
                // below follows the selection (E4B via MLX, or the Edge Gallery
                // E2B `.litertlm` via LiteRT-LM).
                VStack(alignment: .leading, spacing: 9) {
                    MonoLabel(text: "AUTOMATION MODEL")
                    AutomationModelPicker()
                }
                DownloadRow(name: app.models.selectedGemma.menuLabel,
                            subtitle: app.models.selectedGemma.subtitle,
                            phase: app.models.gemma, bytes: app.models.gemmaBytes,
                            download: { app.models.downloadGemma() },
                            pause: { app.models.pauseGemma() },
                            resume: { app.models.resumeGemma() })
            }
            .frame(width: 460).padding(.top, 26)
            Spacer()
            VStack(spacing: 10) {
                Button(app.models.bothReady ? "Continue" : "Continue without models") { step = 5 }
                    .buttonStyle(app.models.bothReady ? AnyButtonStyle(ORBPrimaryButtonStyle()) : AnyButtonStyle(ORBSecondaryButtonStyle()))
                    .frame(width: 280)
                if !app.models.bothReady {
                    Text("You can download or finish these later from the Dashboard.")
                        .font(ORBTheme.mono(10)).foregroundStyle(ORBTheme.ink3)
                }
            }
            .padding(.bottom, 46)
        }
        .onAppear { app.models.refresh() }
    }

    private var tutorialScreen: some View {
        VStack(spacing: 0) {
            header(6)
            Spacer()
            Text("Try saying…").font(ORBTheme.ui(24, weight: .semibold))
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(hex: "FBE9DC"), Color(hex: "F3F1EC")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 14).stroke(ORBTheme.accent, lineWidth: 3)
                    .shadow(color: ORBTheme.accent.opacity(0.5), radius: 12)
                HStack(spacing: 12) {
                    Circle().fill(RadialGradient(colors: [Color(hex: "FFC58A"), ORBTheme.accent],
                                                 center: .topLeading, startRadius: 1, endRadius: 22))
                        .frame(width: 22, height: 22)
                    Text("“Send a WhatsApp to Mom that I’m running late”")
                        .font(ORBTheme.ui(14, weight: .medium)).foregroundStyle(.white)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "1A1714").opacity(0.86)))
            }
            .frame(width: 460, height: 150).padding(.top, 22)

            HStack(spacing: 10) {
                tag("⌘ L TO TALK"); tag("GLOW = AGENT WORKING"); tag("SPEAK NATURALLY")
            }
            .padding(.top, 18)
            Spacer()
            Button("Get Started") { onFinish() }.buttonStyle(ORBPrimaryButtonStyle()).frame(width: 280).padding(.bottom, 46)
        }
    }

    // MARK: Helpers

    private func tag(_ t: String) -> some View {
        Text(t).font(ORBTheme.mono(10.5)).foregroundStyle(ORBTheme.ink2)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(ORBTheme.card)).overlay(Capsule().stroke(ORBTheme.line))
    }

    private func permissionScreen(n: Int, icon: String, title: String, body: String,
                                  status: PermissionsManager.Status, primaryTitle: String,
                                  primary: @escaping () -> Void, note: String,
                                  reset: (() -> Void)? = nil) -> some View {
        VStack(spacing: 0) {
            header(n)
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(ORBTheme.accentSoft).frame(width: 84, height: 84)
                Image(systemName: icon).font(.system(size: 30, weight: .medium)).foregroundStyle(ORBTheme.accent)
            }
            Text(title).font(ORBTheme.ui(24, weight: .semibold)).padding(.top, 28)
            Text(body).font(ORBTheme.ui(14)).foregroundStyle(ORBTheme.ink2)
                .multilineTextAlignment(.center).frame(width: 400).padding(.top, 12)

            statusRow(status)
                .frame(width: 420).padding(.top, 24)

            Button(primaryTitle, action: primary).buttonStyle(ORBPrimaryButtonStyle()).frame(width: 260).padding(.top, 22)
            Button("Continue") { step += 1 }
                .buttonStyle(.plain).font(ORBTheme.ui(14, weight: .semibold))
                .foregroundStyle(status == .granted ? ORBTheme.accent : ORBTheme.ink3)
                .padding(.top, 14)
            MonoLabel(text: note).padding(.top, 14)
            // Dev builds get re-signed each rebuild, so a previously-granted
            // permission can keep showing "waiting". Let the user clear the stale
            // grant and try again without leaving onboarding.
            if let reset, status != .granted {
                Button("Still says waiting? Reset & try again", action: reset)
                    .buttonStyle(.plain).font(ORBTheme.ui(12, weight: .medium))
                    .foregroundStyle(ORBTheme.ink3).padding(.top, 10)
            }
            Spacer()
        }
    }

    @ViewBuilder private func statusRow(_ status: PermissionsManager.Status) -> some View {
        HStack(spacing: 12) {
            Circle().fill(status == .granted ? ORBTheme.success : ORBTheme.warning).frame(width: 9, height: 9)
            Text(status == .granted ? "Permission granted" : "Waiting for permission…")
                .font(ORBTheme.ui(13)).foregroundStyle(ORBTheme.ink2)
            Spacer()
            if status == .granted {
                Image(systemName: "checkmark").foregroundStyle(ORBTheme.success).font(.system(size: 14, weight: .bold))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 10).fill(ORBTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ORBTheme.line))
    }
}

struct DownloadRow: View {
    let name: String, subtitle: String
    let phase: ModelManager.Phase
    let bytes: (Int64, Int64)
    let download: () -> Void
    let pause: () -> Void
    let resume: () -> Void

    private var progress: Double { phase.fraction }
    private var isReady: Bool { phase.isReady }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isReady ? ORBTheme.success : ORBTheme.accentSoft)
                        .frame(width: 34, height: 34)
                    switch phase {
                    case .ready:
                        Image(systemName: "checkmark").foregroundStyle(.white).font(.system(size: 14, weight: .heavy))
                    case .downloading:
                        ProgressView().controlSize(.small)
                    case .paused:
                        Image(systemName: "pause.fill").foregroundStyle(ORBTheme.ink3).font(.system(size: 13))
                    case .failed:
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(ORBTheme.danger).font(.system(size: 13))
                    case .notDownloaded:
                        Image(systemName: "arrow.down").foregroundStyle(ORBTheme.accent).font(.system(size: 13, weight: .bold))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(ORBTheme.ui(15, weight: .semibold))
                    Text(detail).font(ORBTheme.mono(11)).foregroundStyle(ORBTheme.ink3)
                }
                Spacer()
                trailing
            }
            ProgressView(value: progress).tint(isReady ? ORBTheme.success : ORBTheme.accent)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(ORBTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ORBTheme.line))
    }

    @ViewBuilder private var trailing: some View {
        switch phase {
        case .ready:
            Text("DONE").font(ORBTheme.mono(12, weight: .semibold)).foregroundStyle(ORBTheme.success)
        case .downloading:
            HStack(spacing: 10) {
                Text("\(Int(progress * 100))%").font(ORBTheme.mono(12, weight: .semibold)).foregroundStyle(ORBTheme.accent)
                Button("Pause", action: pause).buttonStyle(.borderless)
                    .font(ORBTheme.ui(12, weight: .semibold)).foregroundStyle(ORBTheme.accent)
            }
        case .paused:
            HStack(spacing: 10) {
                Text("\(Int(progress * 100))%").font(ORBTheme.mono(12, weight: .semibold)).foregroundStyle(ORBTheme.ink3)
                Button("Resume", action: resume).buttonStyle(.borderless)
                    .font(ORBTheme.ui(12, weight: .semibold)).foregroundStyle(ORBTheme.accent)
            }
        case .notDownloaded:
            Button("Download", action: download).buttonStyle(.borderless).font(ORBTheme.ui(12, weight: .semibold)).foregroundStyle(ORBTheme.accent)
        case .failed:
            Button("Retry", action: download).buttonStyle(.borderless).font(ORBTheme.ui(12, weight: .semibold)).foregroundStyle(ORBTheme.danger)
        }
    }

    private var detail: String {
        switch phase {
        case .failed(let msg): return msg.uppercased()
        case .downloading where bytes.1 > 0:
            return "\(subtitle) · \(Self.fmt(bytes.0)) / \(Self.fmt(bytes.1))"
        case .paused where bytes.1 > 0:
            return "PAUSED · \(Self.fmt(bytes.0)) / \(Self.fmt(bytes.1))"
        default: return subtitle
        }
    }

    private static func fmt(_ b: Int64) -> String {
        let mb = Double(b) / 1_048_576
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}

/// Choose which Gemma variant drives automation. Tapping a card makes it the
/// active model (`AppState.selectAutomationModel`); a check marks installed ones.
/// Shared by onboarding and Settings.
struct AutomationModelPicker: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(spacing: 8) {
            ForEach(GemmaVariant.allCases) { v in
                let selected = app.models.selectedGemma == v
                Button { app.selectAutomationModel(v) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(v.displayName).font(ORBTheme.ui(13, weight: .semibold))
                            Spacer(minLength: 0)
                            if app.models.phase(for: v).isReady {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(ORBTheme.success).font(.system(size: 11))
                            } else if selected {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundStyle(ORBTheme.accent).font(.system(size: 11))
                            }
                        }
                        Text(v.blurb).font(ORBTheme.mono(9)).foregroundStyle(ORBTheme.ink3)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text(v.approxSizeLabel).font(ORBTheme.mono(9, weight: .semibold))
                            .foregroundStyle(selected ? ORBTheme.accent : ORBTheme.ink3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9).fill(selected ? ORBTheme.accentSoft : ORBTheme.card))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .stroke(selected ? ORBTheme.accent : ORBTheme.line, lineWidth: selected ? 1.5 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Type-erasing button style wrapper so we can switch styles conditionally.
struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { config in AnyView(style.makeBody(configuration: config)) }
    }
    func makeBody(configuration: Configuration) -> some View { makeBodyClosure(configuration) }
}
