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

            // Type a command instead of speaking it.
            CommandInputField().padding(.top, 18)

            if !app.models.bothReady {
                VStack(spacing: 8) {
                    Text("Models aren't installed yet")
                        .font(ORBTheme.ui(12, weight: .semibold)).foregroundStyle(ORBTheme.warning)
                    Button("Finish setup") { app.openSetup() }
                        .buttonStyle(ORBPrimaryButtonStyle())
                }
                .padding(.top, 12)
            } else if let msg = app.errorMessage {
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

            // Status pills (reflect the real model state)
            HStack(spacing: 8) {
                statusPill("GEMMA", ready: app.models.gemma.isReady)
                statusPill("MOONSHINE", ready: app.models.moonshine.isReady)
            }
            .padding(.top, 12)
        }
        .padding(24)
    }

    private func statusPill(_ text: String, ready: Bool) -> some View {
        HStack(spacing: 7) {
            Circle().fill(ready ? ORBTheme.success : ORBTheme.ink3).frame(width: 7, height: 7)
            Text(ready ? "\(text) READY" : "\(text) OFF")
                .font(ORBTheme.mono(10)).foregroundStyle(ORBTheme.ink2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(ORBTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ORBTheme.line))
    }
}

/// Inline text entry: type a command and run it through the same pipeline as
/// voice. Submits on Return or the send button; the button is disabled (and the
/// field never fires) when there's nothing actionable to run.
struct CommandInputField: View {
    @EnvironmentObject private var app: AppState
    @State private var text = ""
    @FocusState private var focused: Bool

    private var canSend: Bool { AppState.normalizedCommand(text) != nil }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.cursor")
                .font(.system(size: 12))
                .foregroundStyle(ORBTheme.ink3)

            TextField("Type a command…", text: $text)
                .textFieldStyle(.plain)
                .font(ORBTheme.ui(13))
                .foregroundStyle(ORBTheme.ink)
                .focused($focused)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(canSend ? ORBTheme.accent : ORBTheme.ink3))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Run command")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(ORBTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(focused ? ORBTheme.accent.opacity(0.6) : ORBTheme.line))
    }

    private func send() {
        // Only clear the field when something actionable was actually submitted,
        // so an accidental Return on whitespace doesn't wipe in-progress typing.
        guard canSend else { return }
        app.submitTextCommand(text)
        text = ""
    }
}
