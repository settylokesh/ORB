//
//  Theme.swift
//  ORB
//
//  Central design tokens mirrored from the ORB design spec.
//

import SwiftUI

enum ORBTheme {
    // Brand
    static let accent       = Color(hex: "FF6A1A")
    static let accentDeep   = Color(hex: "E8500F")
    static let accentSoft   = Color(hex: "FFF1E8")
    static let board        = Color(hex: "E9E6E1")
    static let ink          = Color(hex: "1A1714")
    static let ink2         = Color(hex: "6B6660")
    static let ink3         = Color(hex: "9A938B")
    static let line         = Color.black.opacity(0.09)
    static let card         = Color(hex: "FFFFFF")
    static let surface      = Color(hex: "FBFAF8")

    // Semantic
    static let success      = Color(hex: "28C840")
    static let warning      = Color(hex: "FEBC2E")
    static let danger       = Color(hex: "FF3B30")

    // Fonts
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

/// A small monospaced uppercase label used for section headers / metadata.
struct MonoLabel: View {
    let text: String
    var color: Color = ORBTheme.ink3
    var size: CGFloat = 10
    var body: some View {
        Text(text)
            .font(ORBTheme.mono(size, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(color)
    }
}

/// Status pill ("READY", "NEEDED", "GRANTED").
struct StatusPill: View {
    enum Kind { case good, warn, bad, neutral }
    let text: String
    var kind: Kind = .good

    private var dot: Color {
        switch kind {
        case .good: return ORBTheme.success
        case .warn: return ORBTheme.warning
        case .bad: return ORBTheme.danger
        case .neutral: return ORBTheme.ink3
        }
    }
    private var bg: Color {
        switch kind {
        case .good: return Color(hex: "EAF7EC")
        case .warn: return Color(hex: "FFF7E6")
        case .bad: return Color(hex: "FDECEA")
        case .neutral: return ORBTheme.board
        }
    }
    private var fg: Color {
        switch kind {
        case .good: return Color(hex: "1E8B33")
        case .warn: return Color(hex: "9A7414")
        case .bad: return ORBTheme.danger
        case .neutral: return ORBTheme.ink2
        }
    }
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(text).font(ORBTheme.mono(11, weight: .semibold)).foregroundStyle(fg)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(bg))
    }
}

/// Primary filled accent button look used throughout the spec.
struct ORBPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ORBTheme.ui(15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 12).padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(ORBTheme.accent))
            .shadow(color: ORBTheme.accent.opacity(0.5), radius: 10, x: 0, y: 6)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

/// Secondary outlined button.
struct ORBSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ORBTheme.ui(14, weight: .semibold))
            .foregroundStyle(ORBTheme.ink)
            .padding(.vertical, 11).padding(.horizontal, 18)
            .background(RoundedRectangle(cornerRadius: 10).fill(ORBTheme.card))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ORBTheme.line))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
