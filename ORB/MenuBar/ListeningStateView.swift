//
//  ListeningStateView.swift
//  ORB
//

import SwiftUI

struct ListeningStateView: View {
    @EnvironmentObject private var app: AppState
    @State private var dotPulse = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(ORBTheme.accent).frame(width: 8, height: 8)
                        .overlay(Circle().stroke(ORBTheme.accent.opacity(0.18), lineWidth: 4))
                        .scaleEffect(dotPulse ? 1.25 : 1)
                        .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { dotPulse = true } }
                    Text("Listening…").font(ORBTheme.ui(13, weight: .semibold)).foregroundStyle(ORBTheme.accent)
                }
                Spacer()
                Text("MOONSHINE · 16kHz").font(ORBTheme.mono(11)).foregroundStyle(ORBTheme.ink3)
            }

            WaveformView(level: app.audioLevel).padding(.top, 26)

            // Live transcript
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: "TRANSCRIBING")
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(app.transcript)
                        .font(ORBTheme.ui(17, weight: .medium))
                        .foregroundStyle(ORBTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    BlinkingCursor()
                }
                .frame(minHeight: 48, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(ORBTheme.card))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ORBTheme.line))
            .padding(.top, 24)

            HStack {
                Text("AUTO-STOPS AFTER \(String(format: "%.1f", app.settings.silenceTimeout))s SILENCE")
                    .font(ORBTheme.mono(10)).foregroundStyle(ORBTheme.ink3)
                Spacer()
                Button("Stop") { app.cancel() }
                    .buttonStyle(.plain)
                    .font(ORBTheme.ui(13, weight: .semibold))
                    .foregroundStyle(ORBTheme.ink2)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(ORBTheme.card))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ORBTheme.line))
            }
            .padding(.top, 16)
        }
        .padding(24)
    }
}
