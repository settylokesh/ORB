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

/// The small ringed orb used in headers / sidebar — the ORB logo mark.
///
/// Mirrors the design lockup: a tilted orbit (faded behind the sphere, solid
/// where it crosses in front), the glowing core, a highlight, and the node dot
/// riding the front of the orbit.
struct OrbLogoMark: View {
    var size: CGFloat = 30
    var body: some View {
        Canvas { ctx, _ in
            let s = size
            func scaled(_ v: CGFloat) -> CGFloat { v / 168 * s }
            let center = CGPoint(x: scaled(84), y: scaled(84))
            let rx = scaled(78), ry = scaled(29)
            let tilt = -26.0 * .pi / 180.0
            let cosT = cos(tilt), sinT = sin(tilt)

            // A point on the tilted orbit for parameter angle `deg`.
            func orbit(_ deg: Double) -> CGPoint {
                let t = deg * .pi / 180.0
                let x = rx * cos(t), y = ry * sin(t)
                return CGPoint(x: center.x + cosT * x - sinT * y,
                               y: center.y + sinT * x + cosT * y)
            }
            func arcPath(_ from: Double, _ to: Double) -> Path {
                var p = Path()
                let steps = 48
                for i in 0...steps {
                    let d = from + (to - from) * Double(i) / Double(steps)
                    let pt = orbit(d)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                return p
            }

            // Back of the orbit (full ellipse, faded, behind the sphere).
            ctx.stroke(arcPath(0, 360),
                       with: .color(ORBTheme.accentDeep.opacity(0.34)),
                       style: StrokeStyle(lineWidth: scaled(5), lineCap: .round))

            // Glowing core.
            let core = Path(ellipseIn: CGRect(x: scaled(40), y: scaled(40), width: scaled(88), height: scaled(88)))
            ctx.fill(core, with: .radialGradient(
                Gradient(colors: [Color(hex: "FFEAD4"), Color(hex: "FF9F52"), ORBTheme.accent, Color(hex: "D9490C")]),
                center: CGPoint(x: scaled(72), y: scaled(64)),
                startRadius: 0, endRadius: scaled(62)))

            // Specular highlight.
            let hi = Path(ellipseIn: CGRect(x: scaled(55), y: scaled(55), width: scaled(30), height: scaled(22)))
            ctx.fill(hi, with: .color(.white.opacity(0.5)))

            // Front of the orbit (lower half, crosses in front of the sphere).
            ctx.stroke(arcPath(20.5, 200.5),
                       with: .linearGradient(
                        Gradient(colors: [Color(hex: "FF8A3D"), ORBTheme.accentDeep]),
                        startPoint: orbit(20.5), endPoint: orbit(200.5)),
                       style: StrokeStyle(lineWidth: scaled(5), lineCap: .round))

            // Node riding the front of the orbit.
            let nodeC = orbit(20.5)
            let nodeR = scaled(7)
            ctx.fill(Path(ellipseIn: CGRect(x: nodeC.x - nodeR, y: nodeC.y - nodeR,
                                            width: nodeR * 2, height: nodeR * 2)),
                     with: .color(ORBTheme.accentDeep))
        }
        .frame(width: size, height: size)
        .shadow(color: ORBTheme.accent.opacity(0.45), radius: size * 0.16)
    }
}
