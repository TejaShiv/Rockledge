import SwiftUI

struct HeartSheet: View {
    let monitor: HeartMonitor
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
                SheetHeader(title: "heart") {
                    Task { await monitor.refresh() }
                } onClose: {
                    dismiss()
                }

                Spacer()
                reading
                Spacer()
                stats.padding(.bottom, 44)
            }
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
        .task { await monitor.refresh() }
    }

    private var reading: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(monitor.latestBPM.map(String.init) ?? "—")
                    .font(.system(size: 96, weight: .heavy).width(.expanded).monospacedDigit())
                    .foregroundStyle(Palette.bone)
                    .contentTransition(.numericText())
                    .shadow(color: Palette.red.opacity(0.65), radius: 34)
                    .shadow(color: Palette.red.opacity(0.4), radius: 12)

                Text("bpm")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(Palette.bone.opacity(0.4))
            }

            Text(monitor.freshness ?? "no readings")
                .font(.system(size: 10, weight: .black))
                .tracking(1.6)
                .foregroundStyle(Palette.redHot.opacity(0.75))
        }
    }

    private var stats: some View {
        VStack(spacing: 22) {
            HStack(spacing: 30) {
                StatPill(monitor.todayRange.map { "\($0.low)–\($0.high)" } ?? "—", "today")
                StatPill(monitor.restingBPM.map(String.init) ?? "—", "resting")
                StatPill("\(monitor.sampleCountToday)", "readings")
            }
            HStack(spacing: 30) {
                StatPill(monitor.hrv.map { "\($0)ms" } ?? "—", "hrv")
                StatPill(monitor.spo2.map { "\($0)%" } ?? "—", "oxygen")
            }
        }
    }
}

// MARK: - Shared sheet furniture

struct SheetHeader: View {
    let title: String
    var showRefresh: Bool = true
    let onRefresh: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.black))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Palette.bone.opacity(0.6))
                    .background(Circle().fill(Palette.steel))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(.caption.weight(.black))
                .tracking(2)
                .foregroundStyle(Palette.bone.opacity(0.5))

            Spacer()

            if showRefresh {
                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.black))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(Palette.bone.opacity(0.6))
                        .background(Circle().fill(Palette.steel))
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 34, height: 34)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

struct StatPill: View {
    let value: String
    let label: String

    init(_ value: String, _ label: String) {
        self.value = value
        self.label = label
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .black).monospacedDigit())
                .foregroundStyle(Palette.bone.opacity(0.85))
            Text(label)
                .font(.system(size: 9, weight: .black))
                .tracking(1.4)
                .foregroundStyle(Palette.bone.opacity(0.35))
        }
    }
}
