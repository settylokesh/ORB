//
//  DashboardView.swift
//  ORB
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Dashboard").font(ORBTheme.ui(22, weight: .bold))

                HStack(spacing: 30) {
                    VStack(spacing: 14) {
                        Button(action: { app.activate() }) { OrbView(size: 128) }
                            .buttonStyle(.plain)
                        MonoLabel(text: "⌘ SPACE TO TALK", color: ORBTheme.ink2, size: 11)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        MonoLabel(text: "LAST TRANSCRIPT")
                        Text(app.lastRecord.map { "“\($0.transcript)”" } ?? "“Say a command to get started”")
                            .font(ORBTheme.ui(18, weight: .medium))
                            .padding(.top, 8)
                        if let last = app.lastRecord {
                            HStack(spacing: 8) {
                                Text(last.result == .success ? "✓ Completed in \(last.duration.secondsLabel)" : "✗ Failed")
                                    .font(ORBTheme.ui(12, weight: .semibold))
                                    .foregroundStyle(last.result == .success ? ORBTheme.success : ORBTheme.danger)
                                Text("·").foregroundStyle(ORBTheme.ink3)
                                Text("\(last.steps.count) actions").font(ORBTheme.ui(12)).foregroundStyle(ORBTheme.ink2)
                            }
                            .padding(.top, 14)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ORBTheme.card))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ORBTheme.line))
                }
                .padding(.top, 24)

                // Model cards
                HStack(spacing: 14) {
                    modelCard(app.gemmaStatus, ramLabel: "RAM (LOADED)", metricSuffix: "")
                    modelCard(app.moonshineStatus, ramLabel: "RAM (LOADED)", metricSuffix: "")
                }
                .padding(.top, 22)

                MonoLabel(text: "RECENT").padding(.top, 22)
                VStack(spacing: 8) {
                    ForEach(history.records.prefix(4)) { rec in
                        HStack(spacing: 12) {
                            Circle().fill(rec.result == .success ? ORBTheme.success : ORBTheme.danger)
                                .frame(width: 8, height: 8)
                            Text(rec.transcript).font(ORBTheme.ui(13)).lineLimit(1)
                            Spacer()
                            Text("\(rec.date.relativeLabel) · \(rec.duration.secondsLabel)")
                                .font(ORBTheme.mono(11)).foregroundStyle(ORBTheme.ink3)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ORBTheme.card))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ORBTheme.line))
                    }
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 38).padding(.vertical, 34)
        }
    }

    private func modelCard(_ m: ModelStatus, ramLabel: String, metricSuffix: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(m.name).font(ORBTheme.ui(14, weight: .semibold))
                Spacer()
                StatusPill(text: m.isReady ? "READY" : "OFF", kind: m.isReady ? .good : .neutral)
            }
            HStack(spacing: 18) {
                metric(value: m.metric, unit: m.metricLabel, label: "SPEED/LATENCY")
                metric(value: ramValue(m.ramMB), unit: ramUnit(m.ramMB), label: ramLabel)
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(ORBTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ORBTheme.line))
    }

    private func ramValue(_ mb: Int) -> String {
        guard mb > 0 else { return "—" }
        return mb >= 1024 ? String(format: "%.1f", Double(mb) / 1024) : "\(mb)"
    }
    private func ramUnit(_ mb: Int) -> String { mb >= 1024 ? "GB" : "MB" }

    private func metric(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(ORBTheme.ui(19, weight: .bold))
                Text(unit).font(ORBTheme.ui(12)).foregroundStyle(ORBTheme.ink3)
            }
            Text(label).font(ORBTheme.mono(9.5)).foregroundStyle(ORBTheme.ink3)
        }
    }
}
