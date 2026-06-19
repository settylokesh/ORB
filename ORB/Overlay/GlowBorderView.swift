//
//  GlowBorderView.swift
//  ORB
//
//  The animated glowing edge drawn inside the transparent overlay window.
//

import SwiftUI
import Combine

@MainActor
final class GlowModel: ObservableObject {
    @Published var mode: GlowMode = .hidden
}

struct GlowBorderView: View {
    @ObservedObject var model: GlowModel
    @State private var pulse = false

    private var color: Color {
        switch model.mode {
        case .hidden:    return .clear
        case .planning, .executing: return ORBTheme.accent
        case .success:   return ORBTheme.success
        case .failure:   return ORBTheme.danger
        }
    }

    private var isPulsing: Bool {
        model.mode == .planning || model.mode == .executing
    }

    private var baseOpacity: Double {
        switch model.mode {
        case .hidden:    return 0
        case .planning:  return 0.55
        case .executing: return 0.7
        case .success, .failure: return 1
        }
    }

    var body: some View {
        GeometryReader { geo in
            let radius: CGFloat = 14
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(color, lineWidth: 3.5)
                .shadow(color: color.opacity(0.9), radius: 18)
                .shadow(color: color.opacity(0.6), radius: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(color.opacity(0.5), lineWidth: 1)
                        .blur(radius: 6)
                )
                .padding(2)
                .frame(width: geo.size.width, height: geo.size.height)
                .opacity(model.mode == .hidden ? 0 : (isPulsing ? (pulse ? 1.0 : baseOpacity) : baseOpacity))
        }
        .ignoresSafeArea()
        .onAppear { restartPulse() }
        .onChange(of: model.mode) { _ in restartPulse() }
    }

    private func restartPulse() {
        pulse = false
        guard isPulsing else { return }
        let duration = model.mode == .executing ? 0.75 : 1.5
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}
