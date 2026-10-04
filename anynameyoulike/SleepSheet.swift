import SwiftUI

struct SleepSheet: View {
    let monitor: SleepMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.inkLow, Palette.ink],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                SheetHeader(title: "sleep") {
                    Task { await monitor.refresh() }
                } onClose: {
                    dismiss()
                }

                Spacer()

                if monitor.segments.isEmpty {
                    VStack(spacing: 8) {
                        Text("—")
                            .font(.system(size: 72, weight: .heavy).width(.expanded))
                            .foregroundStyle(Palette.bone.opacity(0.3))
                        Text(monitor.diagnostic.isEmpty ? "no sleep recorded" : monitor.diagnostic)
                            .font(.caption.weight(.bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Palette.bone.opacity(0.4))
                            .padding(.horizontal, 40)
                        Text("check Mi Fitness is syncing sleep to Health")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.bone.opacity(0.25))
                    }
                } else {
                    duration
                    hypnogram
                        .padding(.top, 34)
                        .padding(.horizontal, 24)
                }

                Spacer()

                if !monitor.segments.isEmpty {
                    stageBreakdown.padding(.bottom, 44)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
        .task { await monitor.refresh() }
    }

    private var duration: some View {
        VStack(spacing: 4) {
            Text(monitor.durationText)
                .font(.system(size: 72, weight: .heavy).width(.expanded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(Palette.bone)
                .shadow(color: Palette.red.opacity(0.5), radius: 30)

            if let bed = monitor.inBed {
                Text("\(time(bed.start)) to \(time(bed.end))")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Palette.bone.opacity(0.4))
            }
        }
    }

    private var hypnogram: some View {
        GeometryReader { geo in
            let total = monitor.segments.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }

            HStack(spacing: 1) {
                ForEach(monitor.segments) { segment in
                    let share = segment.end.timeIntervalSince(segment.start) / max(total, 1)

                    Rectangle()
                        .fill(colour(for: segment.stage))
                        .frame(width: max(geo.size.width * share, 1))
                        .frame(height: height(for: segment.stage, in: geo.size.height))
                        .frame(height: geo.size.height, alignment: .bottom)
                }
            }
        }
        .frame(height: 110)
    }

    private func height(for stage: SleepMonitor.Stage, in full: CGFloat) -> CGFloat {
        switch stage {
        case .deep: return full
        case .core: return full * 0.72
        case .rem: return full * 0.46
        case .awake: return full * 0.2
        }
    }

    private func colour(for stage: SleepMonitor.Stage) -> Color {
        switch stage {
        case .deep: return Palette.red
        case .core: return Palette.redHot.opacity(0.75)
        case .rem: return Color(red: 1.0, green: 0.55, blue: 0.45).opacity(0.7)
        case .awake: return Palette.bone.opacity(0.28)
        }
    }

    private var stageBreakdown: some View {
        HStack(spacing: 26) {
            ForEach([SleepMonitor.Stage.deep, .core, .rem, .awake], id: \.rawValue) { stage in
                let mins = monitor.minutes(in: stage)
                VStack(spacing: 3) {
                    Rectangle()
                        .fill(colour(for: stage))
                        .frame(width: 18, height: 3)
                    Text(mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins)m")
                        .font(.system(size: 14, weight: .black).monospacedDigit())
                        .foregroundStyle(Palette.bone.opacity(0.85))
                    Text(stage.label)
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(Palette.bone.opacity(0.35))
                }
            }
        }
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
