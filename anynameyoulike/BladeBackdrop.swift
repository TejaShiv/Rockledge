//
//  BladeBackdrop.swift
//  anynameyoulike
//
//  Created by Tejas Shivaprasad on 9/24/26.
//


import SwiftUI

struct BladeBackdrop: View {
    var roll: Double
    var pitch: Double

    private struct Blade: Identifiable {
        let id: Int
        let x: CGFloat
        let width: CGFloat
        let depth: CGFloat
        let accent: Bool
    }

    /// (width, gap after, is accent). Medium density: reads as slats, not a barcode.
    private static let pattern: [(CGFloat, CGFloat, Bool)] = [
        (25, 13, false), (10, 9, true), (33, 17, false), (7, 11, false),
        (18, 14, true), (28, 10, false), (9, 16, false), (22, 12, false),
        (13, 9, true), (30, 15, false), (8, 11, false), (20, 13, false),
        (11, 10, true), (26, 16, false), (16, 11, false), (9, 14, false),
        (23, 12, false), (12, 9, true), (29, 15, false), (8, 11, false)
    ]

    private static let blades: [Blade] = {
        var result: [Blade] = []
        var cursor: CGFloat = 0
        for (index, item) in pattern.enumerated() {
            result.append(
                Blade(
                    id: index,
                    x: cursor,
                    width: item.0,
                    depth: CGFloat(4 + (index % 5) * 7),
                    accent: item.2
                )
            )
            cursor += item.0 + item.1
        }
        return result
    }()

    private static let span: CGFloat = {
        guard let last = blades.last else { return 1 }
        return last.x + last.width
    }()

    var body: some View {
        GeometryReader { geo in
            let originX = (geo.size.width - Self.span) / 2
            let tall = geo.size.height * 1.7

            // 2D hotspot: roll picks which blades catch light, pitch picks where on them
            let specX = 0.5 + roll * 0.42
            let specY = 0.5 + pitch * 0.46

            ZStack(alignment: .topLeading) {
                ForEach(Self.blades) { blade in
                    let center = (blade.x + blade.width / 2) / Self.span
                    let lit = max(0, 1 - abs(center - specX) / 0.19)

                    Rectangle()
                        .fill(fill(lit: lit, accent: blade.accent, specY: specY))
                        .frame(width: blade.width, height: tall)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(edge(lit: lit, accent: blade.accent, specY: specY))
                                .frame(width: 1)
                        }
                        .offset(
                            x: originX + blade.x + CGFloat(roll) * blade.depth,
                            y: -geo.size.height * 0.35 + CGFloat(pitch) * blade.depth * 0.6
                        )
                }
            }
            .rotationEffect(.degrees(6), anchor: .center)
            .overlay {
                RadialGradient(
                    colors: [
                        Color.black.opacity(0.86),
                        Color.black.opacity(0.5),
                        Color.black.opacity(0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: geo.size.width * 0.9
                )
            }
        }
        .ignoresSafeArea()
        .drawingGroup()
    }

    /// Vertical band inside each blade, tracking pitch, so the hotspot is 2D.
    private func fill(lit: Double, accent: Bool, specY: Double) -> LinearGradient {
        let dim = tone(lit: lit * 0.26, accent: accent)
        let hot = tone(lit: lit, accent: accent)
        let y = min(max(specY, 0.06), 0.94)

        return LinearGradient(
            stops: [
                .init(color: dim, location: 0),
                .init(color: dim, location: max(y - 0.32, 0.001)),
                .init(color: hot, location: y),
                .init(color: dim, location: min(y + 0.32, 0.999)),
                .init(color: dim, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func tone(lit: Double, accent: Bool) -> Color {
        if accent {
            return Color(
                red: 0.165 + lit * 0.70,
                green: 0.014 + lit * 0.10,
                blue: 0.032 + lit * 0.16
            )
        }
        let v = 0.062 + lit * 0.34
        return Color(red: v, green: v * 0.96, blue: v * 1.08)
    }

    private func edge(lit: Double, accent: Bool, specY: Double) -> LinearGradient {
        let base = accent ? Color(red: 1.0, green: 0.30, blue: 0.36) : Color.white
        let y = min(max(specY, 0.06), 0.94)
        let strong = base.opacity(accent ? 0.34 + lit * 0.56 : 0.08 + lit * 0.34)
        let weak = base.opacity(accent ? 0.09 : 0.025)

        return LinearGradient(
            stops: [
                .init(color: weak, location: 0),
                .init(color: weak, location: max(y - 0.36, 0.001)),
                .init(color: strong, location: y),
                .init(color: weak, location: min(y + 0.36, 0.999)),
                .init(color: weak, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}