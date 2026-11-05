import MapKit
import SwiftUI

struct TransitDashboard: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private var transit: Transit { Shared.transit }
    private var arrival: ArrivalAlert { Shared.arrival }
    private var motion: MotionTilt { Shared.motion }
    private let haptics = Shared.haptics

    /// The list is the default: at a glance you want the names and how far,
    /// which read straight off a list without panning or waiting for tiles.
    /// The map is a tap away and is where the live buses are.
    @State private var showMap = false
    @State private var camera: MapCameraPosition = .automatic

    /// The map taking over the screen. The list, the header and the toggles
    /// go with it.
    @State private var fullscreen = false
    /// What the map is actually looking at, so the two sizes can hand it
    /// over instead of snapping back to the stop.
    @State private var region: MKCoordinateRegion?

    /// A pin tapped for a look, which is not the same as choosing the stop:
    /// choosing one reloads the whole screen, and peeking at a pin should
    /// not throw away what you were reading.
    @State private var peek: TransitStop?
    @State private var peekArrivals: [TransitArrival] = []
    @State private var peekLoading = false
    @State private var peekTask: Task<Void, Never>?

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
                ScreenHeader(title: "mbta", trailing: AnyView(headerButtons)) {
                    dismiss()
                }

                ScrollView {
                    VStack(spacing: 12) {
                        arrivalPanel
                        nextPanel
                        if !transit.alerts.isEmpty { alertsPanel }
                        pickerPanel
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
            .opacity(fullscreen ? 0 : 1)

            if fullscreen {
                mapSurface(expanded: true)
                    .ignoresSafeArea()
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(1)
            }
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task {
            // The only place the app asks where you are, and only once the
            // screen is actually open. Always starts from the nearest stop.
            // Something on screen before the network answers, rather than a
            // world map.
            recenter()
            await transit.locate()
            recenter()
            transit.startPolling()
        }
        .onDisappear {
            // Nothing polls behind the user's back.
            transit.stopPolling()
            peekTask?.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { transit.startPolling() } else { transit.stopPolling() }
        }

    }

    private var headerButtons: some View {
        HStack(spacing: 8) {
            Button {
                haptics.soft()
                Task {
                    await transit.selectHomeStop()
                    recenter()
                }
            } label: {
                Image(systemName: transit.isOnHomeStop ? "star.fill" : "star")
                    .font(.footnote.weight(.black))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(
                        transit.isOnHomeStop
                        ? Palette.redHot.opacity(0.9)
                        : Palette.bone.opacity(0.6)
                    )
                    .background(Circle().fill(Palette.steel))
            }
            .buttonStyle(.plain)

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
    }

    private func recenter() {
        guard let stop = transit.stop else { return }
        camera = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: stop.latitude, longitude: stop.longitude
                ),
                latitudinalMeters: 900,
                longitudinalMeters: 900
            )
        )
    }

    // MARK: Waking you up at the right stop

    /// Armed against one stop at a time, and visible the whole time it is
    /// set — an alert you cannot see is one you cannot trust to call off.
    @ViewBuilder
    private var arrivalPanel: some View {
        if let armed = arrival.watch {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Palette.redHot)

                    Text("alert set")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.6)
                        .foregroundStyle(Palette.redHot)

                    Spacer(minLength: 8)

                    Button {
                        haptics.soft()
                        arrival.cancel()
                    } label: {
                        Text("cancel")
                            .font(.system(size: 9, weight: .black))
                            .tracking(1.2)
                            .foregroundStyle(Palette.bone.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Palette.steel))
                    }
                    .buttonStyle(.plain)
                }

                Text(armed.name)
                    .font(.system(size: 17, weight: .heavy))
                    .lineLimit(2)
                    .foregroundStyle(Palette.bone)

                Text("your phone will wake you about half a mile out, even locked")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.bone.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassBackdrop(cornerRadius: 28, tint: Palette.redHot.opacity(0.10))

        } else if let stop = transit.stop {
            VStack(alignment: .leading, spacing: 10) {
                Text("wake me near a stop")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.6)
                    .foregroundStyle(Palette.bone.opacity(0.3))

                HStack(spacing: 12) {
                    Text(stop.name)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(2)
                        .foregroundStyle(Palette.bone.opacity(0.85))

                    Spacer(minLength: 8)

                    Button {
                        haptics.commit()
                        arrival.arm(stop)
                    } label: {
                        Group {
                            if arrival.isArming {
                                ProgressView().controlSize(.mini).tint(Palette.ink)
                            } else {
                                Text("go")
                                    .font(.system(size: 12, weight: .black))
                                    .tracking(1.4)
                            }
                        }
                        .frame(width: 52, height: 32)
                        .foregroundStyle(Palette.ink)
                        .background(Capsule().fill(Palette.redHot.opacity(0.9)))
                    }
                    .buttonStyle(.plain)
                    .disabled(arrival.isArming)
                }

                if let note = arrival.note {
                    Text(note)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.redHot.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassBackdrop(cornerRadius: 28, tint: Palette.bone.opacity(0.06))
        }
    }

    // MARK: Picking a stop

    private var pickerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(transit.usedFallback ? "stops near the home stop" : "stops near you")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.6)
                    .foregroundStyle(Palette.bone.opacity(0.3))

                Spacer()

                modeToggle
            }

            if showMap {
                if fullscreen {
                    // Holds the space so coming back out does not make the
                    // panel jump.
                    Color.clear.frame(height: Self.mapHeight)
                } else {
                    stopMap
                }
            } else {
                stopList
            }

            if !transit.servingRoutes.isEmpty {
                // Naming the routes means a bus that is not on the map reads
                // as one that does not stop here, rather than as a bug.
                Text("buses shown: \(transit.servingRoutes.joined(separator: " · ")) — the routes that stop here")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.bone.opacity(0.3))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackdrop(cornerRadius: 28, tint: Palette.bone.opacity(0.06))
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { wantsMap in
                Button {
                    haptics.soft()
                    showMap = wantsMap
                    if wantsMap { recenter() }
                } label: {
                    Text(wantsMap ? "map" : "list")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(
                            showMap == wantsMap
                            ? Palette.bone.opacity(0.9)
                            : Palette.bone.opacity(0.3)
                        )
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background {
                            if showMap == wantsMap {
                                Capsule().fill(Palette.red.opacity(0.75))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Palette.steel))
    }

    /// A row is about 34pt, so this is four and a half of them: enough to
    /// choose from without the list taking over the screen, and the half row
    /// showing says there is more below.
    private static let stopListHeight: CGFloat = 155

    private var stopList: some View {
        ScrollView {
            stopRows
        }
        .frame(height: Self.stopListHeight)
        .scrollIndicators(.visible)
    }

    private var stopRows: some View {
        VStack(spacing: 0) {
            if transit.nearbyStops.isEmpty {
                Text("no stops found nearby")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.bone.opacity(0.4))
                    .padding(.vertical, 6)
            }

            ForEach(transit.nearbyStops) { stop in
                Button {
                    haptics.soft()
                    Task {
                        await transit.select(stop)
                        recenter()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: stop.id == transit.stop?.id
                              ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(
                                stop.id == transit.stop?.id
                                ? Palette.redHot.opacity(0.9)
                                : Palette.bone.opacity(0.25)
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(stop.name)
                                .font(.system(size: 14, weight: .bold))
                                .lineLimit(1)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(Palette.bone.opacity(0.85))

                            if stop.isPaired {
                                Text("both sides")
                                    .font(.system(size: 8, weight: .black))
                                    .tracking(1)
                                    .foregroundStyle(Palette.bone.opacity(0.28))
                            }
                        }

                        Spacer(minLength: 8)

                        if let away = metres(to: stop) {
                            Text(away)
                                .font(.system(size: 11, weight: .black).monospacedDigit())
                                .foregroundStyle(Palette.bone.opacity(0.35))
                        }
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Measured from the same point the list is sorted from, so the numbers
    /// agree with the order they are shown in.
    private func metres(to stop: TransitStop) -> String? {
        guard let from = transit.origin else { return nil }
        let away = MBTA.distance(from.latitude, from.longitude, stop.latitude, stop.longitude)
        guard away >= 1 else { return nil }
        return away < 1000 ? "\(Int(away))m" : String(format: "%.1fkm", away / 1000)
    }

    static let mapHeight: CGFloat = 300

    private var stopMap: some View {
        mapSurface(expanded: false)
            .frame(height: Self.mapHeight)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// The map at whichever size it is currently being shown.
    ///
    /// Only ever built once: in the panel, or filling the screen, never
    /// both. A second MKMapView left alive behind the first would keep
    /// drawing every pin update off screen for nothing.
    private func mapSurface(expanded: Bool) -> some View {
        ZStack(alignment: .bottom) {
            Map(position: $camera) {
                UserAnnotation()

                ForEach(transit.nearbyStops) { stop in
                    Annotation("", coordinate: CLLocationCoordinate2D(
                        latitude: stop.latitude, longitude: stop.longitude
                    )) {
                        Button {
                            haptics.soft()
                            openPeek(stop)
                        } label: {
                            stopPin(
                                selected: stop.id == transit.stop?.id,
                                peeked: stop.id == peek?.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                ForEach(transit.vehicles) { bus in
                    Annotation("", coordinate: CLLocationCoordinate2D(
                        latitude: bus.latitude, longitude: bus.longitude
                    )) {
                        busPin(bus)
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excluding(.publicTransport)))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            // Keeps the system controls out from under the size button,
            // which sits in the same corner they default to. Fullscreen the
            // button is pushed clear of the notch as well, so the controls
            // have to come down by the same amount.
            .safeAreaPadding(.top, 46 + (expanded ? insets.top : 0))
            // Remembered rather than read back later: a map that has been
            // panned must open at the same place in the other size.
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
            }

            if let stop = peek {
                peekPanel(for: stop, expanded: expanded)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    // Closed by its own button or by dragging it down. There
                    // used to be a transparent sheet across the whole map to
                    // catch a tap anywhere outside the panel, and it
                    // swallowed every pan and pinch with it: the map could
                    // not be moved at all while the panel was up.
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { drag in
                                if drag.translation.height > 40 { closePeek() }
                            }
                    )
            }
        }
        .overlay(alignment: .topTrailing) { sizeToggle(expanded: expanded) }
        .overlay(alignment: .bottomLeading) { cadence(expanded: expanded) }
    }

    private func sizeToggle(expanded: Bool) -> some View {
        Button {
            haptics.soft()
            holdCamera()
            withAnimation(.easeInOut(duration: 0.3)) { fullscreen.toggle() }
        } label: {
            Image(systemName: expanded
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .black))
                .frame(width: 34, height: 34)
                .foregroundStyle(Palette.bone.opacity(0.85))
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Palette.ink.opacity(0.72))
                )
        }
        .buttonStyle(.plain)
        .padding(10)
        .padding(.top, expanded ? insets.top : 0)
    }

    /// Hands the view across before the other size is built, so the map
    /// opens where it was left rather than back at the stop. Not a recenter:
    /// the camera still only moves to a stop when a stop is deliberately
    /// chosen.
    ///
    /// Only the centre and the width are carried over. Handing over the whole
    /// region instead makes the map visibly zoom out on the way back, because
    /// the tall fullscreen region has to be squeezed into a 300pt box to
    /// still fit. Holding the longitude span keeps the scale steady and lets
    /// the extra height simply reveal more.
    private func holdCamera() {
        guard let region else { return }
        camera = .region(
            MKCoordinateRegion(
                center: region.center,
                span: MKCoordinateSpan(
                    latitudeDelta: 0.0001,
                    longitudeDelta: region.span.longitudeDelta
                )
            )
        )
    }

    @ViewBuilder
    private func cadence(expanded: Bool) -> some View {
        // Hidden under the panel, where it would only be in the way.
        if !transit.servingRoutes.isEmpty, peek == nil {
            // Just the cadence: the routes are named under the map, and
            // spelling them out again here spanned the whole width and sat
            // on top of the bus pins.
            Text("every 12s")
                .font(.system(size: 9, weight: .black))
                .tracking(1)
                .foregroundStyle(Palette.bone.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Palette.ink.opacity(0.8)))
                .padding(10)
                .padding(.bottom, expanded ? insets.bottom : 0)
        }
    }

    /// A view that ignores the safe area cannot read it back, and the
    /// fullscreen map runs under the notch and the home indicator on
    /// purpose. The window still knows.
    private var insets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?.safeAreaInsets ?? .zero
    }

    // MARK: A stop you tapped

    private func openPeek(_ stop: TransitStop) {
        peekTask?.cancel()
        peekArrivals = []
        withAnimation(.easeOut(duration: 0.22)) { peek = stop }

        peekTask = Task {
            peekLoading = true
            defer { peekLoading = false }

            // Asked for separately rather than taken from the engine: the
            // engine holds the chosen stop's predictions, and peeking must
            // not overwrite them.
            let found = (try? await MBTA.arrivals(at: stop.queryIDs)) ?? []
            guard !Task.isCancelled else { return }
            peekArrivals = found
        }
    }

    private func closePeek() {
        peekTask?.cancel()
        peekTask = nil
        peekArrivals = []
        withAnimation(.easeIn(duration: 0.18)) { peek = nil }
    }

    private func peekPanel(for stop: TransitStop, expanded: Bool) -> some View {
        // Grouped by headsign through the engine's own function, so this
        // reads exactly like the list below the map.
        let groups = Transit.grouped(peekArrivals)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.name)
                        .font(.system(size: 15, weight: .heavy))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(Palette.bone)

                    if stop.isPaired {
                        Text("both sides")
                            .font(.system(size: 8, weight: .black))
                            .tracking(1)
                            .foregroundStyle(Palette.bone.opacity(0.45))
                    }
                }

                Spacer(minLength: 4)

                if stop.id != transit.stop?.id {
                    Button {
                        haptics.soft()
                        closePeek()
                        Task {
                            await transit.select(stop)
                            recenter()
                        }
                    } label: {
                        Text("show")
                            .font(.system(size: 9, weight: .black))
                            .tracking(1.2)
                            .foregroundStyle(Palette.bone.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Palette.red.opacity(0.75)))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    haptics.soft()
                    closePeek()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .black))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(Palette.bone.opacity(0.6))
                        .background(Circle().fill(Palette.steel.opacity(0.85)))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            if peekLoading, peekArrivals.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .tint(Palette.bone.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else if groups.isEmpty {
                Text("nothing predicted here right now")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.bone.opacity(0.45))
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(groups, id: \.destination) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundStyle(Palette.redHot.opacity(0.6))

                                    Text("towards \(group.destination.lowercased())")
                                        .font(.system(size: 9, weight: .black))
                                        .tracking(1.4)
                                        .foregroundStyle(Palette.bone.opacity(0.4))
                                }

                                if group.arrivals.isEmpty {
                                    Text("nothing predicted this way")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Palette.bone.opacity(0.35))
                                } else {
                                    // Two each way: enough to know whether to
                                    // run for this one.
                                    ForEach(Array(group.arrivals.prefix(2))) { arrival in
                                        arrivalRow(arrival)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: expanded ? 320 : 168)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14 + (expanded ? insets.bottom : 0))
        .frame(maxWidth: .infinity, alignment: .leading)
        // Translucent on purpose: the pin you tapped stays visible behind it.
        .background(.ultraThinMaterial)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 18,
                style: .continuous
            )
        )
    }

    private func stopPin(selected: Bool, peeked: Bool) -> some View {
        Image(systemName: selected ? "largecircle.fill.circle" : "circle.fill")
            .font(.system(size: selected ? 20 : 11, weight: .black))
            .foregroundStyle(selected ? Palette.redHot : Palette.bone.opacity(0.75))
            .shadow(color: .black.opacity(0.6), radius: 2)
            .overlay {
                // A ring, so the pin being read about is obvious without
                // pretending it is the chosen stop.
                if peeked {
                    Circle()
                        .strokeBorder(Palette.bone.opacity(0.9), lineWidth: 2)
                        .frame(width: selected ? 30 : 21, height: selected ? 30 : 21)
                }
            }
    }

    /// Route number, and how many stops short of you it is when the bus can
    /// be tied to one of the arrivals listed below.
    private func busPin(_ bus: TransitVehicle) -> some View {
        VStack(spacing: 1) {
            Text(bus.route)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(Palette.bone)

            if let away = bus.stopsAwayLabel {
                Text(away)
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(Palette.bone.opacity(0.75))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Palette.red)
                .shadow(color: .black.opacity(0.7), radius: 3)
        )
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

    /// Every way out of here, each under where it actually goes, rather than
    /// guessing which one you wanted and hiding the other.
    private var directionsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(transit.byDestination, id: \.destination) { group in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(Palette.redHot.opacity(0.6))

                        Text("towards \(group.destination.lowercased())")
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
        .opacity(transit.byDestination.isEmpty ? 0 : 1)
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
