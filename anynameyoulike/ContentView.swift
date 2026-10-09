import SwiftUI
import UserNotifications

// MARK: - Theme

enum Palette {
    static let ink = Color(red: 0.035, green: 0.031, blue: 0.043)
    static let inkLow = Color(red: 0.090, green: 0.024, blue: 0.047)
    static let steel = Color(red: 0.110, green: 0.102, blue: 0.118)
    static let bone = Color(red: 0.941, green: 0.929, blue: 0.914)
    static let red = Color(red: 0.90, green: 0.075, blue: 0.157)
    static let redHot = Color(red: 1.0, green: 0.28, blue: 0.34)
}

// MARK: - Home

struct ContentView: View {
    private let writer = StepWriter()
    private let haptics = Shared.haptics
    private var motion: MotionTilt { Shared.motion }
    private var pantry: Pantry { Shared.pantry }
    private var transit: Transit { Shared.transit }

    @State private var steps: Int?
    @State private var rota = TrashRota.load()
    @State private var showTrash = false
    @State private var showBackup = false
    @State private var sharingFile: ExportedFile?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Palette.inkLow, Palette.ink],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .ignoresSafeArea()

                BladeBackdrop(roll: motion.roll, pitch: motion.pitch)

                VStack(spacing: 14) {
                    TrashBar(rota: rota) {
                        haptics.soft()
                        showTrash = true
                    }
                    .padding(.top, 6)

                    NavigationLink {
                        HealthDashboard()
                    } label: {
                        DoorCard(
                            icon: "heart.text.square.fill",
                            title: "health",
                            value: steps.map { $0.formatted(.number) } ?? "—",
                            caption: "steps today",
                            tint: Palette.redHot.opacity(0.75)
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { haptics.soft() })

                    NavigationLink {
                        GroceryDashboard()
                    } label: {
                        GroceryDoorCard(
                            lines: stockLines,
                            emptyMessage: "nothing tracked yet"
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { haptics.soft() })

                    NavigationLink {
                        TransitDashboard()
                    } label: {
                        TransitDoorCard(
                            lines: transitLines,
                            emptyMessage: "no buses to ruggles right now",
                            staleNote: transitStaleNote
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { haptics.soft() })

                    Spacer()

                    HStack(spacing: 12) {
                        Signature()

                        Button {
                            haptics.soft()
                            showBackup = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 12, weight: .black))
                                .frame(width: 30, height: 30)
                                .foregroundStyle(Palette.bone.opacity(0.3))
                                .background(Circle().fill(Palette.steel.opacity(0.7)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Palette.redHot)
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showTrash) {
            TrashSheet(rota: $rota, haptics: haptics)
        }
        .sheet(item: $sharingFile) { file in
            ShareSheet(url: file.url)
        }
        .sheet(isPresented: $showBackup) {
            BackupSheet(haptics: haptics) {
                // The document underneath has been swapped out.
                rota = TrashRota.load()
                pantry.reload()
                transit.reloadFromStore()
                Task { await refresh() }
            }
        }
        .onAppear {
            if !reduceMotion { motion.start() }
            landFromNotification()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { landFromNotification() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refresh() }
            }
        }
        .task {
            // A dated copy a day, before anything can change the document.
            Backup.Snapshots.writeIfDue()
            nagToExportIfOverdue()

            await HealthAuth.request()
            await TrashReminder.reschedule(rota)
            await NightlyReminder.apply()
            await refresh()
        }
    }

    /// The three things closest to running out, soonest first.
    private var stockLines: [StockLine] {
        pantry.items
            .sorted { pantry.daysLeft(for: $0) < pantry.daysLeft(for: $1) }
            .prefix(3)
            .map { item in
                let days = pantry.daysLeft(for: item)
                return StockLine(
                    id: item.id,
                    name: item.name.lowercased(),
                    days: daysText(remaining: item.remaining, days: days),
                    urgency: urgency(days: days, remaining: item.remaining)
                )
            }
    }

    private func daysText(remaining: Double, days: Double) -> String {
        if remaining <= 0 { return "out" }
        if days < 1 { return "today" }
        if days < 2 { return "1 day" }
        if days > 30 { return "30+ days" }
        return "\(Int(days.rounded())) days"
    }

    private func urgency(days: Double, remaining: Double) -> Color {
        if remaining <= 0 || days <= 2 { return Palette.redHot }
        if days <= 7 { return Palette.red.opacity(0.85) }
        return Palette.bone.opacity(0.3)
    }

    private var transitLines: [TransitLine] {
        transit.homeLines.map { arrival in
            TransitLine(
                id: arrival.id,
                route: arrival.route,
                destination: arrival.headsign,
                minutes: "\(arrival.minutes()) min"
            )
        }
    }

    /// Only shown when the times are left over from an earlier fetch.
    private var transitStaleNote: String? {
        guard transit.homeIsStale, let at = transit.homeFetchedAt else { return nil }
        return "as of \(Self.clock.string(from: at))"
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Puts the share sheet up on launch when the last copy to leave the app
    /// is more than five days old.
    ///
    /// The sheet itself rather than a banner: losing the container costs
    /// everything, and a banner is the easiest thing in the world to swipe
    /// away without reading. It is still dismissible — it just defaults to
    /// being in the way.
    ///
    /// Once per launch, from `.task`, so coming back from the background does
    /// not keep raising it.
    private func nagToExportIfOverdue() {
        guard sharingFile == nil, !showBackup else { return }

        let document = Store.document
        guard Backup.isExportOverdue(
            lastExport: Backup.lastExport,
            hasContent: Backup.Summary(document).isWorthKeeping
        ) else { return }

        guard let file = try? Backup.exportFile() else { return }
        sharingFile = ExportedFile(url: file)
    }

    /// A tap on the nightly reminder lands here, on the destination picker
    /// itself rather than on the backup screen.
    ///
    /// Presented from here rather than from inside the backup sheet: a sheet
    /// raised on top of a sheet that is still animating in gets dropped, and
    /// the tap quietly did nothing.
    ///
    /// This is not a silent backup. iOS wants somewhere to put the file and
    /// only the user can say where, so the tap gets as far as asking.
    private func landFromNotification() {
        guard Shared.router.take() == .export else { return }

        if let file = try? Backup.exportFile() {
            sharingFile = ExportedFile(url: file)
        } else {
            // Nothing to share, so fall back to the screen that explains it
            // rather than doing nothing at all.
            showBackup = true
        }
    }

    private func refresh() async {
        steps = await writer.todayTotal()
        rota = TrashRota.load()
        // Pinned to the home stop, so the home screen never asks where you
        // are and opening the app cannot trigger a location prompt.
        await transit.refreshHomeStop()
    }
}

/// A URL on its own cannot drive a sheet; this gives it the identity
/// `sheet(item:)` needs.
private struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

#Preview {
    ContentView()
}
