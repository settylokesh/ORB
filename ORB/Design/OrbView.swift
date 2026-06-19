//
//  OrbView.swift
//  ORB
//
//  The glowing orb centerpiece + the small ringed logo mark.
//

import SwiftUI

/// The big breathing orb with an optional mic glyph (idle/listening states).
struct OrbView: View {
    var size: CGFloat = 110
    var showMic: Bool = true
    var animated: Bool = true

    @State private var breathing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Color(hex: "FFE6CC"), location: 0.0),
                            .init(color: Color(hex: "FF9A4D"), location: 0.30),
                            .init(color: ORBTheme.accent, location: 0.56),
                            .init(color: ORBTheme.accentDeep, location: 1.0),
                        ],
                        center: UnitPoint(x: 0.36, y: 0.30),
                        startRadius: 0,
                        endRadius: size * 0.62
                    )
                )
                .overlay(
                    Ellipse()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: size * 0.26, height: size * 0.18)
                        .offset(x: -size * 0.13, y: -size * 0.16)
                        .blur(radius: 2)
                )
                .shadow(color: ORBTheme.accent.opacity(0.42), radius: 19, x: 0, y: 0)
                .shadow(color: ORBTheme.accent.opacity(0.20), radius: 40, x: 0, y: 0)

            if showMic {
                MicGlyph(color: .white)
                    .frame(width: size * 0.20, height: size * 0.34)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(breathing ? 1.045 : 1.0)
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

/// Simple microphone glyph drawn with shapes (matches the spec's CSS mic).
struct MicGlyph: View {
    var color: Color = .white
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .top) {
                Capsule()
                    .fill(color)
                    .frame(width: w, height: h * 0.78)
                // stand
                Rectangle()
                    .fill(color)
                    .frame(width: max(2, w * 0.1), height: h * 0.16)
                    .offset(y: h * 0.80)
                // base
                Capsule()
                    .fill(color)
                    .frame(width: w * 0.7, height: max(2, h * 0.06))
                    .offset(y: h * 0.94)
            }
            .frame(width: w, height: h, alignment: .top)
        }
    }
}

/// The small ringed orb used in headers / sidebar (the logo mark).
struct OrbLogoMark: View {
    var size: CGFloat = 30
    var body: some View {
        Canvas { ctx, _ in
            let s = size
            func scaled(_ v: CGFloat) -> CGFloat { v / 168 * s }
            let center = CGPoint(x: scaled(84), y: scaled(84))

            // back ring (rotated ellipse)
            var ring = Path()
            ring.addEllipse(in: CGRect(x: scaled(6), y: scaled(55), width: scaled(156), height: scaled(58)))
            ctx.drawLayer { layer in
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: .degrees(-26))
                layer.translateBy(x: -center.x, y: -center.y)
                layer.stroke(ring, with: .color(ORBTheme.accentDeep.opacity(0.38)), lineWidth: scaled(6))
            }

            // core
            let core = Path(ellipseIn: CGRect(x: scaled(38), y: scaled(38), width: scaled(92), height: scaled(92)))
            ctx.fill(core, with: .radialGradient(
                Gradient(colors: [Color(hex: "FFEAD4"), Color(hex: "FF9F52"), ORBTheme.accent, Color(hex: "D9490C")]),
                center: CGPoint(x: scaled(72), y: scaled(64)),
                startRadius: 0, endRadius: scaled(64)))
        }
        .frame(width: size, height: size)
        .shadow(color: ORBTheme.accent.opacity(0.45), radius: size * 0.18)
    }
}
