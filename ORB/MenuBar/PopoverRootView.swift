//
//  PopoverRootView.swift
//  ORB
//
//  Routes the 380pt popover between the four agent states.
//

import SwiftUI

struct PopoverRootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Group {
            switch app.state {
            case .idle:
                IdleStateView()
            case .listening:
                ListeningStateView()
            case .planning, .executing:
                ExecutingStateView()
            case .success, .failure:
                ResultStateView()
            }
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.2), value: app.state)
    }
}

struct IdleStateView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ORB").font(ORBTheme.ui(15, weight: .bold)).tracking(2)
                Spacer()
                Text("v1.0").font(ORBTheme.mono(11)).foregroundStyle(ORBTheme.ink3)
            }

            Button(action: { app.activate() }) {
                OrbView(size: 110)
            }
            .buttonStyle(.plain)
            .padding(.top, 26)

            Text("Ready to listen").font(ORBTheme.ui(15, weight: .semibold)).padding(.top, 22)
            HStack(spacing: 4) {
                Text("Press").foregroundStyle(ORBTheme.ink2)
                Text(app.settings.hotkeyDisplay)
                    .font(ORBTheme.mono(11))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 5).fill(ORBTheme.card))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(ORBTheme.line))
                Text("or tap the orb").foregroundStyle(ORBTheme.ink2)
            }
            .font(ORBTheme.ui(13))
            .padding(.top, 5)

            if let msg = app.errorMessage {
                Text(msg).font(ORBTheme.ui(12)).foregroundStyle(ORBTheme.danger)
                    .multilineTextAlignment(.center).padding(.top, 12)
            }

            // Last action
            VStack(alignment: .leading, spacing: 5) {
                MonoLabel(text: "LAST ACTION")
                if let last = app.lastRecord {
                    HStack(spacing: 5) {
                        Text(last.transcript).font(ORBTheme.ui(13)).lineLimit(1)
                        Image(systemName: last.result == .success ? "checkmark" : "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(last.result == .success ? ORBTheme.success : ORBTheme.danger)
                    }
                } else {
                    Text("No commands yet").font(ORBTheme.ui(13)).foregroundStyle(ORBTheme.ink3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(ORBTheme.card))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ORBTheme.line))
            .padding(.top, 22)

            // Status pills
            HStack(spacing: 8) {
                statusPill("GEMMA READY")
                statusPill("MOONSHINE")
            }
            .padding(.top, 12)
        }
        .padding(24)
    }

    private func statusPill(_ text: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(ORBTheme.success).frame(width: 7, height: 7)
            Text(text).font(ORBTheme.mono(10)).foregroundStyle(ORBTheme.ink2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(ORBTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ORBTheme.line))
    }
}
