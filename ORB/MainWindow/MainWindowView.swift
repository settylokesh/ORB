//
//  MainWindowView.swift
//  ORB
//
//  Sidebar + content. Dashboard / History / Settings / Permissions / About
//  share the same live data store as the popover.
//

import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ORBTheme.surface)
        }
        .frame(minWidth: 960, minHeight: 640)
        .background(ORBTheme.surface)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                OrbLogoMark(size: 30)
                Text("ORB").font(ORBTheme.ui(16, weight: .bold)).tracking(2)
            }
            .padding(.horizontal, 20).padding(.top, 38).padding(.bottom, 18)

            VStack(spacing: 3) {
                ForEach(MainTab.allCases) { tab in
                    navItem(tab)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            systemCard
                .padding(12)
        }
        .frame(width: 230)
        .background(Color(hex: "F4F2EE").opacity(0.7))
    }

    private func navItem(_ tab: MainTab) -> some View {
        let active = app.selectedTab == tab
        return Button(action: { app.selectedTab = tab }) {
            HStack(spacing: 10) {
                Image(systemName: icon(for: tab))
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(active ? ORBTheme.accent : ORBTheme.ink2)
                Text(tab.title).font(ORBTheme.ui(14, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(active ? ORBTheme.ink : ORBTheme.ink2)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(active ? ORBTheme.accentSoft : .clear)
            )
            .overlay(alignment: .leading) {
                if active {
                    Rectangle().fill(ORBTheme.accent).frame(width: 2).clipShape(Capsule())
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func icon(for tab: MainTab) -> String {
        switch tab {
        case .dashboard:   return "square.grid.2x2"
        case .history:     return "clock.arrow.circlepath"
        case .settings:    return "gearshape"
        case .permissions: return "lock.shield"
        case .about:       return "info.circle"
        }
    }

    private var systemCard: some View {
        let modelsReady = app.models.bothReady
        return VStack(alignment: .leading, spacing: 8) {
            MonoLabel(text: "SYSTEM", size: 9.5)
            HStack(spacing: 7) {
                Circle().fill(app.isBusy ? ORBTheme.warning : ORBTheme.success).frame(width: 7, height: 7)
                Text("\(app.state == .idle ? "Idle" : "Active") · \(app.ram.displayedMB) MB RAM")
                    .font(ORBTheme.ui(11.5)).foregroundStyle(ORBTheme.ink2)
            }
            HStack(spacing: 7) {
                Circle().fill(modelsReady ? ORBTheme.success : ORBTheme.warning).frame(width: 7, height: 7)
                Text(modelsReady ? "Models ready" : "Models not installed")
                    .font(ORBTheme.ui(11.5)).foregroundStyle(ORBTheme.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(ORBTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ORBTheme.line))
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch app.selectedTab {
        case .dashboard:   DashboardView()
        case .history:     HistoryView()
        case .settings:    SettingsView()
        case .permissions: PermissionsView()
        case .about:       AboutView()
        }
    }
}
