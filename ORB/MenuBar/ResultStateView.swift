//
//  ResultStateView.swift
//  ORB
//

import SwiftUI

struct ResultStateView: View {
    @EnvironmentObject private var app: AppState

    private var success: Bool { app.state == .success }
    private var record: CommandRecord? { app.lastRecord }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(success ? Color(hex: "EAF7EC") : Color(hex: "FDECEA"))
                    .frame(width: 72, height: 72)
                ZStack {
                    Circle().fill(success ? ORBTheme.success : ORBTheme.danger).frame(width: 48, height: 48)
                    Image(systemName: success ? "checkmark" : "xmark")
                        .font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                }
            }
            .padding(.top, 14)

            Text(success ? "Done" : "Couldn’t finish")
                .font(ORBTheme.ui(18, weight: .semibold)).padding(.top, 20)

            Text(success ? (app.currentSummary.isEmpty ? "Command completed." : app.currentSummary)
                         : (app.errorMessage ?? "Something went wrong."))
                .font(ORBTheme.ui(14))
                .foregroundStyle(ORBTheme.ink2)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 8)

            // Stats
            HStack(spacing: 8) {
                stat(value: record.map { $0.duration.secondsLabel } ?? "—", label: "TIME TAKEN")
                stat(value: "\(app.steps.filter { $0.status == .done }.count)/\(max(app.steps.count, 1))", label: "STEPS OK")
                stat(value: "\(record?.retries ?? 0)", label: "RETRIES")
            }
            .padding(.top, 22)

            HStack(spacing: 10) {
                Button("Repeat") { app.repeatLast() }
                    .buttonStyle(ORBPrimaryButtonStyle())
                Button("Done") { app.dismissResult() }
                    .buttonStyle(ORBSecondaryButtonStyle())
            }
            .padding(.top, 16)
        }
        .padding(24)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(ORBTheme.ui(18, weight: .bold))
            Text(label).font(ORBTheme.mono(9.5)).foregroundStyle(ORBTheme.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(ORBTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ORBTheme.line))
    }
}
