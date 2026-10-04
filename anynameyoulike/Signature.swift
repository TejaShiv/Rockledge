import SwiftUI

struct Signature: View {
    private let text = "Developed by Tejas Shivaprasad"

    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        base
            .overlay {
                GeometryReader { geo in
                    let width = geo.size.width
                    let band: CGFloat = 130

                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Palette.redHot.opacity(0.5), location: 0.32),
                            .init(color: .white.opacity(0.95), location: 0.5),
                            .init(color: Palette.redHot.opacity(0.5), location: 0.68),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: band)
                    .offset(x: -band + phase * (width + band * 2))
                    .blendMode(.plusLighter)
                }
                .mask(base)
                .allowsHitTesting(false)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 7.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }

    private var base: some View {
        Text(text)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .tracking(2.2)
            .foregroundStyle(Palette.bone.opacity(0.22))
    }
}
