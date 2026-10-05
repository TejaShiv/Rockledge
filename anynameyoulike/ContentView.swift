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
                        DoorCard(
                            icon: "bus.fill",
                            title: "mbta",
                            value: transit.next.map { "\($0.minutes())" } ?? "—",
                            caption: transit.stop?.name.lowercased() ?? "nearest stop",
                            tint: Palette.redHot.opacity(0.75)
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { haptics.soft() })

                    Spacer()

                    Signature()
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
        .onAppear {
            if !reduceMotion { motion.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refresh() }
            }
        }
        .task {
            await HealthAuth.request()
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            await TrashReminder.reschedule(rota)
            await GroceryReminder.apply()
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

    private func refresh() async {
        steps = await writer.todayTotal()
        rota = TrashRota.load()
        // Only the stop already resolved: the home screen never asks where
        // you are, so opening the app cannot trigger a location prompt.
        await transit.refreshKnownStop()
    }
}

#Preview {
    ContentView()
}
