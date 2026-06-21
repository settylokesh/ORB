//
//  ExecutingStateView.swift
//  ORB
//

import SwiftUI

struct ExecutingStateView: View {
    @EnvironmentObject private var app: AppState

    private var doneCount: Int { app.steps.filter { $0.status == .done }.count }
    private var currentIndex: Int { (app.steps.firstIndex { $0.status == .running } ?? doneCount) + 1 }

    private var headline: String {
        if app.isLoadingModel { return "Loading model…" }
        return app.state == .planning ? "Planning…" : "Working…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(headline)
                        .font(ORBTheme.ui(13, weight: .semibold))
                }
                Spacer()
                if !app.isLoadingModel {
                    Text("STEP \(min(currentIndex, max(app.steps.count,1))) / \(app.steps.count)")
                        .font(ORBTheme.mono(11)).foregroundStyle(ORBTheme.ink3)
                }
            }

            // While the model is loading there are no steps yet — explain the wait
            // instead of showing a blank "Planning…" that looks like a freeze.
            Text(app.isLoadingModel
                 ? "Loading Gemma into memory — this only takes a moment."
                 : (app.currentSummary.isEmpty ? app.transcript : app.currentSummary))
                .font(ORBTheme.ui(14, weight: .medium))
                .padding(.top, 16)

            VStack(spacing: 2) {
                ForEach(app.steps) { step in
                    StepRow(step: step)
                }
            }
            .padding(.top, 14)

            HStack {
                Text("GEMMA VERIFIES EACH STEP").font(ORBTheme.mono(10)).foregroundStyle(ORBTheme.ink3)
                Spacer()
                Button("Cancel") { app.cancel() }
                    .buttonStyle(.plain)
                    .font(ORBTheme.ui(13, weight: .semibold))
                    .foregroundStyle(ORBTheme.danger)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(ORBTheme.card))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ORBTheme.line))
            }
            .padding(.top, 10)
        }
        .padding(24)
    }
}
