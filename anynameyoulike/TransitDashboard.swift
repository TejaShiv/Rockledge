import SwiftUI

struct TransitDashboard: View {
    @Environment(\.dismiss) private var dismiss

    private var transit: Transit { Shared.transit }
    private var motion: MotionTilt { Shared.motion }
    private let haptics = Shared.haptics

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
                ScreenHeader(title: "mbta", trailing: AnyView(refreshButton)) {
                    dismiss()
                }

                ScrollView {
                    VStack(spacing: 12) {
                        nextPanel
                        if !transit.alerts.isEmpty { alertsPanel }
                        arrivalsPanel
                        directionsPanel
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                }
                .refreshable {
                    await transit.locate()
                }
            }
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task {
            // The only place the app asks where you are, and only once the
            // screen is actually open.
            await transit.locate()
        }
    }

    private var refreshButton: some View {
        Button {
            haptics.soft()
            Task { await transit.locate() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.footnote.weight(.black))
                .frame(width: 34, height: 34)
                .foregroundStyle(Palette.bone.opacity(transit.isLoading ? 0.25 : 0.6))
                .background(Circle().fill(Palette.steel))
        }
        .buttonStyle(.plain)
        .disabled(transit.isLoading)
    }

    // MARK: Next

    private var nextPanel: some View {
        VStack(spacing: 10) {
            if let next = transit.next {
                Text("\(next.minutes())")
                    .font(.system(size: 62, weight: .heavy).width(.expanded).monospacedDigit())
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .foregroundStyle(Palette.bone)
                    .contentTransition(.numericText())
                    .shadow(color: Color.black.opacity(0.8), radius: 2, y: 2)
                    .shadow(color: Palette.red.opacity(0.22), radius: 24)

                Text("minutes · \(next.route) to \(next.headsign.lowercased())")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.bone.opacity(0.45))
            } else {
                Text("nothing due")
                    .font(.system(size: 34, weight: .heavy).width(.expanded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .foregroundStyle(Palette.bone.opacity(0.8))

                Text("no buses predicted at this stop right now")
                    .font(.system(size: 11, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.bone.opacity(0.4))
            }

            Text(transit.stop?.name.lowercased() ?? "finding your stop")
                .font(.system(size: 13, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.bone.opacity(0.75))
                .padding(.top, 2)

            notices
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .glassBackdrop(cornerRadius: 32, tint: Palette.bone.opacity(0.06))
    }

    /// Says plainly when the screen is not showing what it would ideally show.
    @ViewBuilder
    private var notices: some View {
        VStack(spacing: 5) {
            if transit.usedFallback {
                notice("using the home stop — location is off", icon: "location.slash.fill")
            }
            if transit.isStale, let at = transit.fetchedAt {
                notice("last updated \(Self.clock.string(from: at))", icon: "wifi.slash")
            }
        }
        .padding(.top, 4)
    }

    private func notice(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .black))
            Text(text)
                .font(.system(size: 10, weight: .black))
                .tracking(0.8)
        }
        .foregroundStyle(Palette.redHot.opacity(0.75))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.steel))
    }

    // MARK: Alerts

    private var alertsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("alerts")
                .font(.system(size: 9, weight: .black))
                .tracking(1.6)
                .foregroundStyle(Palette.bone.opacity(0.3))

            ForEach(transit.alerts) { alert in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(alert.route)
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Palette.bone.opacity(0.9))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Palette.red.opacity(0.8)))

                        Text(alert.label)
                            .font(.system(size: 9, weight: .black))
                            .tracking(1.2)
                            .foregroundStyle(Palette.redHot.opacity(0.8))
                    }

                    Text(alert.header)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.bone.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackdrop(cornerRadius: 28, tint: Palette.bone.opacity(0.06))
    }

    // MARK: Arrivals

    private var arrivalsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("next four")
                .font(.system(size: 9, weight: .black))
                .tracking(1.6)
                .foregroundStyle(Palette.bone.opacity(0.3))

            if transit.upcoming.isEmpty {
                Text(emptyLine)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.bone.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(transit.upcoming.prefix(4))) { arrival in
                    arrivalRow(arrival)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackdrop(cornerRadius: 28, tint: Palette.bone.opacity(0.06))
    }

    /// Overnight there is genuinely nothing to show, and saying so is better
    /// than an empty box that looks like a bug.
    private var emptyLine: String {
        transit.isStale
            ? "nothing predicted, and the last check did not get through"
            : "nothing predicted right now — the buses here have stopped for the night"
    }

    private func arrivalRow(_ arrival: TransitArrival) -> some View {
        HStack(spacing: 12) {
            Text(arrival.route)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Palette.bone.opacity(0.9))
                .frame(minWidth: 34)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(Palette.steel))

            VStack(alignment: .leading, spacing: 1) {
                Text(arrival.headsign)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(Palette.bone.opacity(0.85))

                Text(Self.clock.string(from: arrival.time))
                    .font(.system(size: 10, weight: .black).monospacedDigit())
                    .tracking(0.8)
                    .foregroundStyle(Palette.bone.opacity(0.3))
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(arrival.minutes())")
                    .font(.system(size: 19, weight: .black).monospacedDigit())
                    .foregroundStyle(Palette.bone.opacity(0.9))
                Text("min")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1)
                    .foregroundStyle(Palette.bone.opacity(0.35))
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: Both directions

    /// Both ways, each under where it ends up, rather than guessing which one
    /// you wanted and hiding the other.
    private var directionsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(transit.byDirection, id: \.direction) { group in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(Palette.redHot.opacity(0.6))

                        Text("towards \(group.direction.lowercased())")
                            .font(.system(size: 9, weight: .black))
                            .tracking(1.4)
                            .foregroundStyle(Palette.bone.opacity(0.35))
                    }

                    ForEach(Array(group.arrivals.prefix(4))) { arrival in
                        arrivalRow(arrival)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackdrop(cornerRadius: 28, tint: Palette.bone.opacity(0.06))
        .opacity(transit.byDirection.isEmpty ? 0 : 1)
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
