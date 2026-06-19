//
//  PopoverComponents.swift
//  ORB
//
//  Small shared pieces used by the popover state views.
//

import SwiftUI

/// Animated 7-bar waveform whose amplitude follows the live mic level.
struct WaveformView: View {
    var level: Float
    @State private var animate = false
    private let bars = 7

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<bars, id: \.self) { i in
                Capsule()
                    .fill(i == 3 ? ORBTheme.accentDeep : ORBTheme.accent)
                    .frame(width: 5, height: 46)
                    .scaleEffect(y: barScale(i), anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.08),
                        value: animate)
            }
        }
        .frame(height: 64)
        .onAppear { animate = true }
    }

    private func barScale(_ i: Int) -> CGFloat {
        let amp = CGFloat(min(1, max(0.18, level * 1.6)))
        let base: CGFloat = animate ? 1.0 : 0.3
        // Slight per-bar variation so it never looks static.
        let jitter = [0.9, 1.0, 0.75, 1.0, 0.8, 0.95, 0.7][i % 7]
        return max(0.22, base * amp * jitter)
    }
}

/// One row in the executing step list.
struct StepRow: View {
    let step: ActionStep

    var body: some View {
        HStack(spacing: 11) {
            indicator
            Text(step.title)
                .font(ORBTheme.ui(13, weight: step.status == .running ? .semibold : .regular))
                .foregroundStyle(textColor)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, step.status == .running ? 8 : 0)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(step.status == .running ? ORBTheme.accentSoft : .clear)
        )
    }

    @ViewBuilder private var indicator: some View {
        switch step.status {
        case .done:
            ZStack {
                Circle().fill(ORBTheme.success)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
            }.frame(width: 20, height: 20)
        case .failed:
            ZStack {
                Circle().fill(ORBTheme.danger)
                Image(systemName: "exclamationmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            }.frame(width: 20, height: 20)
        case .running:
            ProgressView().controlSize(.small).frame(width: 20, height: 20)
        case .pending:
            Circle().stroke(Color(hex: "DAD5CD"), lineWidth: 2).frame(width: 20, height: 20)
        }
    }

    private var textColor: Color {
        switch step.status {
        case .pending: return ORBTheme.ink3
        case .running: return ORBTheme.ink
        default:       return ORBTheme.ink2
        }
    }
}

/// A blinking text cursor.
struct BlinkingCursor: View {
    @State private var on = true
    var body: some View {
        Rectangle()
            .fill(ORBTheme.accent)
            .frame(width: 2, height: 18)
            .opacity(on ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { on = false }
            }
    }
}
