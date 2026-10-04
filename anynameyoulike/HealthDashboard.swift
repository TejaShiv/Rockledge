import SwiftUI
import HealthKit
import UserNotifications

struct HealthDashboard: View {
    @Environment(\.dismiss) private var dismiss

    private let writer = StepWriter()
    private let haptics = Shared.haptics
    private var motion: MotionTilt { Shared.motion }
    private var heart: HeartMonitor { Shared.heart }
    private var sleep: SleepMonitor { Shared.sleep }

    @State private var reminderOn = false
    @State private var showHeartSheet = false
    @State private var showSleepSheet = false
    @State private var showReminderSheet = false

    @State private var healthTotal: Int?
    @State private var ownTotal = 0
    @State private var target: Int?

    @State private var holdTimer: Timer?
    @State private var holdCount = 0
    @State private var touchStart: Date?
    @State private var moved: CGFloat = 0

    @State private var editing = false
    @State private var editText = ""
    @FocusState private var fieldFocused: Bool

    @State private var status = ""
    @State private var statusToken = 0
    @State private var isWorking = false
    @State private var confettiTrigger = 0

    @Environment(\.scenePhase) private var scenePhase

    private let autoTarget = 11_000
    private let autoThreshold = 10_000
    private let tapSlop: CGFloat = 16

    private var baseValue: Int { healthTotal ?? 0 }
    private var displayed: Int { target ?? baseValue }
    private var delta: Int { displayed - baseValue }
    private var reduceFloor: Int { max(0, baseValue - ownTotal) }

    private var numberFont: Font {
        .system(size: 62, weight: .heavy)
            .width(.expanded)
            .monospacedDigit()
    }

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
                ScreenHeader(title: "health", trailing: AnyView(bellButton)) {
                    dismiss()
                }
                Spacer(minLength: 0)
                cardStack
                    .padding(.horizontal, 20)
                Spacer(minLength: 0)

                if editing {
                    editActions.padding(.bottom, 26)
                }
                statusLine
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }

            ConfettiLayer(trigger: confettiTrigger)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showHeartSheet) { HeartSheet(monitor: heart) }
        .sheet(isPresented: $showSleepSheet) { SleepSheet(monitor: sleep) }
        .sheet(isPresented: $showReminderSheet) {
            ReminderSheet(isOn: $reminderOn, haptics: haptics)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Cancel") { cancelEdit() }
                    .foregroundStyle(Palette.bone.opacity(0.7))
                Spacer()
                Button("Set") { Task { await commitEdit() } }
                    .fontWeight(.bold)
                    .foregroundStyle(Palette.redHot)
            }
        }
        .onDisappear { cancelHold() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await refreshAll()
                    reminderOn = await DailyReminder.isLive()
                }
            } else {
                cancelHold()
            }
        }
        .task {
            reminderOn = await DailyReminder.isLive()
            if DailyReminder.isEnabled && !reminderOn {
                reminderOn = await DailyReminder.schedule()
            }
            await refreshAll()
            await heart.start()
            await sleep.start()
        }
    }

    // MARK: Cards

    @ViewBuilder
    private var cardStack: some View {
        if editing {
            editorCard
        } else {
            VStack(spacing: 13) {
                HealthCard(icon: "heart.fill", caption: "bpm", iconTint: Palette.redHot.opacity(0.8)) {
                    bigValue(heart.latestBPM.map(String.init) ?? "—", glow: 0.22)
                }
                .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .onTapGesture {
                    haptics.soft()
                    showHeartSheet = true
                }

                HealthCard(icon: "figure.walk", caption: "steps", iconTint: Palette.bone.opacity(0.4)) {
                    stepValue
                }
                .scaleEffect(holdCount > 0 ? 1.0 + CGFloat(holdCount) * 0.012 : 1)
                .overlay {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(
                            Palette.redHot.opacity(Double(holdCount) * 0.3),
                            lineWidth: 1 + CGFloat(holdCount)
                        )
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: holdCount)
                .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .gesture(stepGesture)

                HealthCard(icon: "moon.fill", caption: "last night", iconTint: Palette.bone.opacity(0.45)) {
                    bigValue(sleep.durationText, glow: 0.12)
                }
                .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .onTapGesture {
                    haptics.soft()
                    showSleepSheet = true
                }
            }
        }
    }

    private func bigValue(_ text: String, glow: Double) -> some View {
        Text(text)
            .font(numberFont)
            .minimumScaleFactor(0.3)
            .lineLimit(1)
            .foregroundStyle(glassInk)
            .contentTransition(.numericText())
            .overlay { sheen(for: text) }
            .shadow(color: Color.black.opacity(0.8), radius: 2, y: 2)
            .shadow(color: Palette.red.opacity(glow), radius: 24)
            .padding(.horizontal, 30)
    }

    private var stepValue: some View {
        Text(numberText)
            .font(numberFont)
            .minimumScaleFactor(0.3)
            .lineLimit(1)
            .foregroundStyle(glassInk)
            .contentTransition(.numericText())
            .overlay { sheen(for: numberText) }
            .shadow(color: Color.black.opacity(0.85), radius: 2, y: 2)
            .shadow(color: Palette.red.opacity(delta != 0 ? 0.42 : 0.18), radius: 30)
            .padding(.horizontal, 30)
    }

    private var editorCard: some View {
        HealthCard(icon: "keyboard", caption: "steps", iconTint: Palette.redHot.opacity(0.7)) {
            TextField("", text: $editText)
                .keyboardType(.numberPad)
                .focused($fieldFocused)
                .multilineTextAlignment(.center)
                .font(numberFont)
                .minimumScaleFactor(0.3)
                .lineLimit(1)
                .foregroundStyle(Palette.bone)
                .tint(Palette.redHot)
                .padding(.horizontal, 30)
        }
    }

    // MARK: Glass text

    private var numberText: String {
        healthTotal == nil ? "—" : displayed.formatted(.number)
    }

    private var glassInk: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: Palette.bone, location: 0.42),
                .init(color: Palette.bone.opacity(0.68), location: 0.74),
                .init(color: Palette.bone.opacity(0.86), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func sheen(for text: String) -> some View {
        let p = min(max(0.5 + motion.roll * 0.5, 0.05), 0.95)
        return ZStack {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: max(p - 0.16, 0.001)),
                    .init(color: .white.opacity(0.7), location: p),
                    .init(color: .clear, location: min(p + 0.16, 0.999)),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                colors: [Color.white.opacity(0.85), Color.clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.22)
            )
        }
        .blendMode(.plusLighter)
        .mask(
            Text(text)
                .font(numberFont)
                .minimumScaleFactor(0.3)
                .lineLimit(1)
        )
        .allowsHitTesting(false)
    }

    // MARK: Bell

    private var bellButton: some View {
        Button {
            haptics.soft()
            showReminderSheet = true
        } label: {
            Image(systemName: reminderOn ? "bell.fill" : "bell.slash")
                .font(.system(size: 12, weight: .black))
                .frame(width: 34, height: 34)
                .foregroundStyle(Palette.bone.opacity(reminderOn ? 0.7 : 0.3))
                .background(Circle().fill(Palette.steel))
        }
        .buttonStyle(.plain)
    }

    // MARK: Step gesture

    private var stepGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                moved = max(moved, hypot(value.translation.width, value.translation.height))

                if touchStart == nil {
                    touchStart = Date()
                    startHold()
                }
                if moved > tapSlop { cancelHold() }
            }
            .onEnded { _ in
                let held = touchStart.map { Date().timeIntervalSince($0) } ?? 0
                let wasCounting = holdCount > 0 || holdTimer != nil

                cancelHold()

                if moved <= tapSlop && held < 0.5 && !editing {
                    beginEdit()
                } else if moved <= tapSlop && wasCounting && held < 3.0 {
                    flash("hold three seconds to auto set")
                }

                touchStart = nil
                moved = 0
            }
    }

    private func startHold() {
        guard holdTimer == nil else { return }
        holdCount = 0

        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            holdCount += 1
            haptics.thud(step: holdCount)

            if holdCount >= 3 {
                cancelHold()
                Task { await autoSet() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        withAnimation(.easeOut(duration: 0.2)) { holdCount = 0 }
    }

    private func autoSet() async {
        guard displayed < autoThreshold else {
            haptics.soft()
            flash("already past \(autoThreshold.formatted(.number))")
            return
        }
        haptics.commit()
        target = autoTarget
        await commitDelta()
    }

    // MARK: Editing

    private func beginEdit() {
        guard !editing, !isWorking else { return }
        editText = String(displayed)
        editing = true
        fieldFocused = true
        haptics.soft()
    }

    private func commitEdit() async {
        guard editing else { return }
        if let value = Int(editText.filter(\.isNumber)) {
            target = clamp(value)
        }
        editing = false
        fieldFocused = false
        haptics.commit()

        if delta != 0 { await commitDelta() }
    }

    private func cancelEdit() {
        editing = false
        fieldFocused = false
        target = nil
        haptics.soft()
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, reduceFloor), 2_000_000)
    }

    private var editActions: some View {
        HStack(spacing: 14) {
            Button {
                cancelEdit()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.black))
                    .frame(width: 54, height: 54)
                    .background(Polygon(sides: 6, turn: 30).fill(Palette.steel))
                    .overlay(
                        Polygon(sides: 6, turn: 30)
                            .stroke(Palette.red.opacity(0.5), lineWidth: 1.2)
                    )
                    .foregroundStyle(Palette.bone.opacity(0.75))
            }
            .buttonStyle(.plain)

            Button {
                Task { await commitEdit() }
            } label: {
                Image(systemName: "checkmark")
                    .font(.headline.weight(.black))
                    .frame(width: 54, height: 54)
                    .background(Polygon(sides: 6, turn: 30).fill(Palette.red))
                    .overlay(
                        Polygon(sides: 6, turn: 30)
                            .stroke(Palette.bone.opacity(0.3), lineWidth: 1.2)
                    )
                    .foregroundStyle(Palette.bone)
            }
            .buttonStyle(.plain)
        }
    }

    private var statusLine: some View {
        Text(status)
            .font(.caption2.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.bone.opacity(0.4))
            .frame(minHeight: 16, alignment: .bottom)
            .animation(.easeInOut(duration: 0.25), value: status)
    }

    private func flash(_ message: String) {
        status = message
        statusToken += 1
        let token = statusToken
        Task {
            try? await Task.sleep(for: .seconds(3))
            if token == statusToken { status = "" }
        }
    }

    // MARK: Health

    private func refreshAll() async {
        healthTotal = await writer.todayTotal()
        ownTotal = WriteLedger.ownTotalToday

        if let current = target, let fetched = healthTotal, current == fetched {
            target = nil
        }

        await heart.refresh()
        await sleep.refresh()
    }

    private func commitDelta() async {
        let amount = delta
        guard amount != 0 else { return }

        isWorking = true

        if amount > 0 {
            let outcome = await writer.write(total: amount)
            isWorking = false
            switch outcome {
            case .success:
                target = nil
                confettiTrigger += 1
            case .failure(let reason):
                flash(reason)
            }
        } else {
            let outcome = await writer.reduce(by: -amount)
            isWorking = false
            switch outcome {
            case .removed, .nothingToUndo:
                target = nil
            case .failure(let reason):
                flash(reason)
            }
        }

        healthTotal = await writer.todayTotal()
        ownTotal = WriteLedger.ownTotalToday
    }
}

// MARK: - Confetti

struct ConfettiLayer: View {
    let trigger: Int
    @State private var pieces: [Piece] = []

    struct Piece: Identifiable {
        let id = UUID()
        let x: CGFloat
        let color: Color
        let size: CGFloat
        let delay: Double
        let spin: Double
        let drift: CGFloat
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    ConfettiPieceView(piece: piece, height: geo.size.height)
                }
            }
            .onChange(of: trigger) { _, newValue in
                guard newValue > 0 else { return }
                spawn(width: geo.size.width)
            }
        }
    }

    private func spawn(width: CGFloat) {
        let colors = [Palette.red, Palette.redHot, Palette.bone,
                      Color(red: 0.45, green: 0.45, blue: 0.48)]
        pieces = (0..<40).map { _ in
            Piece(
                x: CGFloat.random(in: 0...max(width, 1)),
                color: colors.randomElement() ?? Palette.red,
                size: CGFloat.random(in: 6...13),
                delay: Double.random(in: 0...0.35),
                spin: Double.random(in: -900...900),
                drift: CGFloat.random(in: -70...70)
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            pieces = []
        }
    }
}

struct ConfettiPieceView: View {
    let piece: ConfettiLayer.Piece
    let height: CGFloat
    @State private var progress: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(piece.color)
            .frame(width: piece.size, height: piece.size * 2.2)
            .rotationEffect(.degrees(piece.spin * progress))
            .opacity(progress > 0.85 ? Double((1 - progress) / 0.15) : 1)
            .position(
                x: piece.x + piece.drift * progress,
                y: -30 + (height + 80) * progress
            )
            .onAppear {
                withAnimation(.easeIn(duration: 1.9).delay(piece.delay)) {
                    progress = 1
                }
            }
    }
}
