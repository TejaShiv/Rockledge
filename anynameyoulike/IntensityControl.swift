import SwiftUI

struct IntensityControl: View {
    @Binding var level: Double
    @Binding var expanded: Bool
    let haptics: GrainHaptics

    @State private var lastPreview: Double = -1

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                    expanded.toggle()
                }
                haptics.soft()
            } label: {
                Image(systemName: expanded ? "chevron.left" : "waveform")
                    .font(.subheadline.weight(.black))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Palette.bone.opacity(0.75))
            }
            .buttonStyle(.plain)

            if expanded {
                Slider(value: $level, in: 0...1)
                    .tint(Palette.red)
                    .frame(width: 186)
                    .scaleEffect(1.12)
                    .frame(height: 40)
                    .onChange(of: level) { _, newValue in
                        haptics.level = CGFloat(newValue)
                        if abs(newValue - lastPreview) > 0.035 {
                            lastPreview = newValue
                            haptics.strike()
                        }
                    }
                    .padding(.horizontal, 6)

                Text("\(Int(level * 100))")
                    .font(.caption.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(Palette.bone.opacity(0.6))
                    .frame(width: 30)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Palette.steel)
                .overlay(Capsule().strokeBorder(Palette.red.opacity(0.4), lineWidth: 1))
        )
    }
}
