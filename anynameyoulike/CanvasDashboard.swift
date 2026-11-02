import SwiftUI

/// One section per class, each in its own colour, each leading with the one
/// thing to do next. Nothing is counted down to the minute and nothing is
/// red: the point is to be able to look at the term without flinching.
struct CanvasDashboard: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var canvas: CanvasBoard { Shared.canvas }
    private var motion: MotionTilt { Shared.motion }

    @State private var showSettings = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.inkLow, Palette.ink],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()

            BladeBackdrop(roll: motion.roll, pitch: motion.pitch)

            VStack(spacing: 0) {
                ScreenHeader(title: "canvas", trailing: AnyView(gear)) {
                    dismiss()
                }

                ScrollView {
                    VStack(spacing: 16) {
                        if let failure = canvas.failure {
                            trouble(failure)
                        }

                        if canvas.snapshot.classes.isEmpty {
                            empty
                        } else {
                            ForEach(canvas.snapshot.classes) { subject in
                                section(subject)
                            }
                        }

                        footer
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 44)
                }
                .refreshable { await canvas.refresh() }
            }
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showSettings) { CanvasSettings() }
        .task {
            // Tapping a card that says "connect canvas" should land on the
            // place where you connect it, not on an empty screen with a
            // button on it.
            if !canvas.isConnected {
                showSettings = true
            } else {
                await canvas.refresh()
            }
        }
    }

    private var gear: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "key.fill")
                .font(.footnote.weight(.black))
                .frame(width: 34, height: 34)
                .foregroundStyle(Palette.bone.opacity(0.6))
                .background(Circle().fill(Palette.steel))
        }
        .buttonStyle(.plain)
    }

    // MARK: A class

    private func section(_ subject: CanvasClass) -> some View {
        let work = canvas.snapshot.outstanding(in: subject.id)
        let soon = Array(
            work.filter { $0.dueAt <= horizon }
        )

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(subject.tint)
                    .frame(width: 8, height: 8)

                Text(subject.title.lowercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.8)
                    .foregroundStyle(subject.tint)

                Spacer(minLength: 8)

                Text(subject.code)
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(Palette.bone.opacity(0.25))
            }
            .padding(.bottom, 12)

            if let next = soon.first {
                nextUp(next, in: subject)

                if soon.count > 1 {
                    VStack(spacing: 0) {
                        ForEach(soon.dropFirst()) { item in
                            row(item, in: subject)
                        }
                    }
                    .padding(.top, 10)
                }
            } else {
                caughtUp
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackdrop(cornerRadius: 28, tint: subject.tint.opacity(0.07))
    }

    private var horizon: Date {
        Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    }

    private func nextUp(_ item: CanvasAssignment,
                        in subject: CanvasClass) -> some View {
        Button {
            open(item)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("next up")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.6)
                    .foregroundStyle(Palette.bone.opacity(0.3))

                Text(item.name)
                    .font(.system(size: 22, weight: .heavy))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(Palette.bone)
                    .padding(.top, 6)

                Text(CanvasDue.phrase(for: item.dueAt))
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(subject.tint)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ item: CanvasAssignment,
                     in subject: CanvasClass) -> some View {
        Button {
            open(item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(item.name)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(Palette.bone.opacity(0.8))

                Spacer(minLength: 8)

                Text(CanvasDue.dayPhrase(for: item.dueAt))
                    .font(.system(size: 12, weight: .black))
                    .lineLimit(1)
                    .foregroundStyle(subject.tint.opacity(0.7))
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var caughtUp: some View {
        Text("All caught up")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Palette.bone.opacity(0.3))
            .padding(.vertical, 4)
    }

    // MARK: Everything else

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: canvas.isConnected ? "graduationcap" : "key")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.bone.opacity(0.25))

            Text(canvas.isConnected ? "No classes found" : "Canvas is not connected")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.bone.opacity(0.45))

            Button(canvas.isConnected ? "Check token" : "Connect Canvas") {
                showSettings = true
            }
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(Palette.bone.opacity(0.75))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Capsule().fill(Palette.steel))
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func trouble(_ failure: CanvasAPI.Failure) -> some View {
        HStack(spacing: 10) {
            Image(systemName: failure.needsNewToken
                  ? "exclamationmark.triangle.fill" : "wifi.slash")
                .font(.system(size: 12, weight: .black))

            Text(failure.message)
                .font(.system(size: 12, weight: .bold))

            Spacer(minLength: 0)

            if failure.needsNewToken || failure == .noToken {
                Button("Fix") { showSettings = true }
                    .font(.system(size: 11, weight: .black))
                    .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Palette.redHot.opacity(0.9))
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.redHot.opacity(0.12))
        )
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if canvas.isLoading {
                ProgressView().controlSize(.mini).tint(Palette.bone.opacity(0.4))
            }

            Text(canvas.lastUpdatedText ?? "Never updated")
                .font(.system(size: 9, weight: .black))
                .tracking(1.2)
                .foregroundStyle(Palette.bone.opacity(0.25))
        }
        .padding(.top, 4)
    }

    private func open(_ item: CanvasAssignment) {
        guard let link = item.link else { return }
        Shared.haptics.soft()
        openURL(link)
    }
}
