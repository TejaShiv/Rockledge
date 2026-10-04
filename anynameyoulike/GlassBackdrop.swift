import SwiftUI

extension View {
    /// Liquid Glass on iOS 26, material fallback below that.
    func glassBackdrop(cornerRadius: CGFloat, tint: Color) -> some View {
        modifier(GlassBackdrop(cornerRadius: cornerRadius, tint: tint))
    }
}

struct GlassBackdrop: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .glassEffect(.clear.tint(tint), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.fill(Color.black.opacity(0.10))
                    // thins the frost so the blades read through
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.30),
                                Color.white.opacity(0.03),
                                Color.white.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                }
        }
    }
}
