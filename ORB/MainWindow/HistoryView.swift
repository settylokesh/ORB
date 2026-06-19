//
//  HistoryView.swift
//  ORB
//

import SwiftUI
import AppKit

struct HistoryView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var history: HistoryStore

    enum Filter: String, CaseIterable { case all = "ALL", success = "SUCCESS", failed = "FAILED" }
    @State private var search = ""
    @State private var filter: Filter = .all

    private var filtered: [CommandRecord] {
        history.records.filter { rec in
            (search.isEmpty || rec.transcript.localizedCaseInsensitiveContains(search)) &&
            (filter == .all ||
             (filter == .success && rec.result == .success) ||
             (filter == .failed && rec.result == .failure))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("History").font(ORBTheme.ui(22, weight: .bold))
                Spacer()
                Button("Export .txt") { exportHistory() }
                    .buttonStyle(ORBSecondaryButtonStyle())
                    .fixedSize()
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(ORBTheme.ink3)
                    TextField("Search commands…", text: $search)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 9).fill(ORBTheme.card))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(ORBTheme.line))

                ForEach(Filter.allCases, id: \.self) { f in
                    Button(f.rawValue) { filter = f }
                        .buttonStyle(.plain)
                        .font(ORBTheme.mono(11, weight: .semibold))
                        .foregroundStyle(filter == f ? ORBTheme.accent : ORBTheme.ink2)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 9)
                            .fill(filter == f ? ORBTheme.accentSoft : ORBTheme.card))
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .stroke(filter == f ? .clear : ORBTheme.line))
                }
            }
            .padding(.top, 18)

            ScrollView {
                VStack(spacing: 9) {
                    ForEach(filtered) { rec in
                        row(rec)
                    }
                }
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 38).padding(.vertical, 34)
    }

    private func row(_ rec: CommandRecord) -> some View {
        let ok = rec.result == .success
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(ok ? ORBTheme.success : ORBTheme.danger).frame(width: 22, height: 22)
                Image(systemName: ok ? "checkmark" : "exclamationmark")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(rec.transcript).font(ORBTheme.ui(14, weight: .medium))
                Text((rec.failureReason ?? rec.steps.joined(separator: " · ")).uppercased())
                    .font(ORBTheme.mono(10.5))
                    .foregroundStyle(ok ? ORBTheme.ink3 : ORBTheme.danger)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(rec.duration.secondsLabel).font(ORBTheme.mono(11)).foregroundStyle(ORBTheme.ink2)
                Text(rec.date.relativeLabel).font(ORBTheme.mono(10)).foregroundStyle(ORBTheme.ink3)
            }
            Button(action: { app.lastRecord = rec; app.repeatLast() }) {
                Image(systemName: "arrow.clockwise").foregroundStyle(ORBTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 11).fill(ORBTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .stroke(ok ? ORBTheme.line : ORBTheme.danger.opacity(0.25)))
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ORB History.txt"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? history.exportText().data(using: .utf8)?.write(to: url)
        }
    }
}
