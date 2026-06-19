//
//  PermissionsView.swift
//  ORB
//

import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject private var permissions: PermissionsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Permissions").font(ORBTheme.ui(22, weight: .bold))
                Spacer()
                Button("↻ Refresh") { permissions.refresh() }
                    .buttonStyle(ORBSecondaryButtonStyle()).fixedSize()
            }
            Text("ORB needs three permissions to hear you, see your screen, and act on your behalf.")
                .font(ORBTheme.ui(14)).foregroundStyle(ORBTheme.ink2).padding(.top, 8)

            VStack(spacing: 12) {
                row(icon: "mic.fill", title: "Microphone",
                    subtitle: "Capture your voice commands",
                    status: permissions.microphone,
                    fix: { Task { await permissions.requestMicrophone() } })
                row(icon: "cursorarrow.click.2", title: "Accessibility",
                    subtitle: "Click, type and navigate any app",
                    status: permissions.accessibility,
                    fix: { permissions.requestAccessibility() })
                row(icon: "rectangle.inset.filled.badge.record", title: "Screen Recording",
                    subtitle: "Read the screen so Gemma can see the UI",
                    status: permissions.screenRecording,
                    fix: { permissions.requestScreenRecording() })
            }
            .padding(.top, 24)

            if permissions.screenRecording != .granted {
                Text("Without Screen Recording, ORB can still hear and type — but it can’t visually verify each step. Grant it for full reliability.")
                    .font(ORBTheme.ui(13)).foregroundStyle(Color(hex: "9A4A14"))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ORBTheme.accentSoft))
                    .padding(.top, 20)
            }

            Spacer()
        }
        .padding(.horizontal, 38).padding(.vertical, 34)
        .onAppear { permissions.refresh() }
    }

    private func row(icon: String, title: String, subtitle: String,
                     status: PermissionsManager.Status, fix: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(status == .granted ? ORBTheme.accentSoft : Color(hex: "FFF7E6"))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(status == .granted ? ORBTheme.accent : Color(hex: "C9962B"))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(ORBTheme.ui(15, weight: .semibold))
                Text(subtitle).font(ORBTheme.ui(13)).foregroundStyle(ORBTheme.ink2)
            }
            Spacer()
            if status == .granted {
                StatusPill(text: "GRANTED", kind: .good)
            } else {
                HStack(spacing: 12) {
                    StatusPill(text: status == .denied ? "NEEDED" : "ASK", kind: .warn)
                    Button("Fix", action: fix)
                        .buttonStyle(.plain)
                        .font(ORBTheme.ui(13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(ORBTheme.accent))
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 12).fill(ORBTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(status == .granted ? ORBTheme.line : ORBTheme.warning.opacity(0.4)))
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            OrbView(size: 110)
            Text("ORB").font(ORBTheme.ui(34, weight: .bold)).tracking(4)
            Text("Speak. Your Mac does the rest.").font(ORBTheme.ui(15)).foregroundStyle(ORBTheme.ink2)
            VStack(spacing: 4) {
                Text("Version 1.0").font(ORBTheme.mono(12)).foregroundStyle(ORBTheme.ink3)
                Text("100% LOCAL · NO ACCOUNT · NO CLOUD").font(ORBTheme.mono(11)).foregroundStyle(ORBTheme.ink3)
                Text("Moonshine STT · Gemma 4 E4B (MLX)").font(ORBTheme.mono(11)).foregroundStyle(ORBTheme.ink3)
            }
            .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
