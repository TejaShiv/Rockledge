import SwiftUI

struct GroceryDashboard: View {
    @Environment(\.dismiss) private var dismiss

    private var pantry: Pantry { Shared.pantry }
    private var motion: MotionTilt { Shared.motion }
    private let haptics = Shared.haptics

    @State private var editing: GroceryItem?
    @State private var creating = false
    @State private var showOrder = false
    @State private var weighing: GroceryItem?
    @State private var typing: GroceryItem?
    @State private var editingMeal: Meal?
    @State private var remindersOn = NightlyReminder.isEnabled
    @State private var showReminder = false

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
                ScreenHeader(title: "groceries", trailing: AnyView(bellButton)) {
                    dismiss()
                }

                ScrollView {
                    VStack(spacing: 12) {
                        orderButton

                        ForEach(pantry.items) { item in
                            ItemRow(
                                item: item,
                                pantry: pantry,
                                haptics: haptics,
                                onEdit: { editing = item },
                                onWeigh: { weighing = item },
                                onTypeAmount: { typing = item }
                            )
                        }

                        addButton
                        mealsPanel
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                }
            }
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(item: $editing) { item in
            ItemEditor(draft: item, pantry: pantry, haptics: haptics)
        }
        .sheet(isPresented: $creating) {
            ItemEditor(draft: nil, pantry: pantry, haptics: haptics)
        }
        .sheet(isPresented: $showOrder) {
            OrderSheet(pantry: pantry, haptics: haptics)
        }
        .sheet(isPresented: $showReminder) {
            ReminderSheet(isOn: $remindersOn, haptics: haptics)
        }
        .sheet(item: $weighing) { item in
            WeighSheet(item: item, pantry: pantry, haptics: haptics)
        }
        .sheet(item: $typing) { item in
            UsedSheet(item: item, pantry: pantry, haptics: haptics)
        }
        .sheet(item: $editingMeal) { meal in
            MealSheet(meal: meal, pantry: pantry, haptics: haptics)
        }
    }

    /// Meals are what Siri logs: "had lunch" takes all of these off at once.
    private var mealsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("meals")
                .font(.system(size: 9, weight: .black))
                .tracking(1.6)
                .foregroundStyle(Palette.bone.opacity(0.3))

            ForEach(pantry.meals) { meal in
                Button {
                    haptics.soft()
                    editingMeal = meal
                } label: {
                    HStack(spacing: 10) {
                        Text(meal.spokenName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Palette.bone.opacity(0.85))

                        Spacer(minLength: 8)

                        Text(summary(of: meal))
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(Palette.bone.opacity(0.35))
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                haptics.soft()
                editingMeal = Meal(name: "")
            } label: {
                Text("+ add a meal")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.bone.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                Palette.bone.opacity(0.14),
                                style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
                            )
                    )
            }
            .buttonStyle(.plain)

            Text("say \"log lunch in Tally\" to log one")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.bone.opacity(0.28))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackdrop(cornerRadius: 28, tint: Palette.bone.opacity(0.06))
    }

    private func summary(of meal: Meal) -> String {
        let parts = meal.portions.compactMap { portion -> String? in
            guard let item = pantry.item(withID: portion.itemID) else { return nil }
            return "\(MealOutcome.trim(portion.amount))\(item.unit) \(item.name.lowercased())"
        }
        return parts.isEmpty ? "nothing in it yet" : parts.joined(separator: ", ")
    }

    /// One reminder covers groceries and steps together, so this opens the
    /// single place it is configured rather than carrying its own switch.
    private var bellButton: some View {
        Button {
            haptics.soft()
            showReminder = true
        } label: {
            Image(systemName: remindersOn ? "bell.fill" : "bell.slash")
                .font(.system(size: 12, weight: .black))
                .frame(width: 34, height: 34)
                .foregroundStyle(Palette.bone.opacity(remindersOn ? 0.7 : 0.3))
                .background(Circle().fill(Palette.steel))
        }
        .buttonStyle(.plain)
    }

    private var orderButton: some View {
        Button {
            haptics.commit()
            showOrder = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "cart.fill")
                    .font(.system(size: 13, weight: .black))
                Text("ORDERING GROCERIES")
                    .font(.system(size: 13, weight: .black))
                    .tracking(1.6)
                Spacer()
                if lowCount > 0 {
                    Text("\(lowCount)")
                        .font(.system(size: 12, weight: .black).monospacedDigit())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.bone.opacity(0.18)))
                }
            }
            .foregroundStyle(Palette.bone)
            .padding(.horizontal, 20)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Palette.red)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Palette.bone.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, 4)
    }

    private var lowCount: Int {
        pantry.items.filter { pantry.daysLeft(for: $0) <= 7 }.count
    }

    private var addButton: some View {
        Button {
            haptics.soft()
            creating = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .black))
                Text("add an item")
                    .font(.system(size: 12, weight: .black))
                    .tracking(1.2)
            }
            .foregroundStyle(Palette.bone.opacity(0.4))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        Palette.bone.opacity(0.14),
                        style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

// MARK: - One item

private struct ItemRow: View {
    let item: GroceryItem
    let pantry: Pantry
    let haptics: GrainHaptics
    let onEdit: () -> Void
    let onWeigh: () -> Void
    let onTypeAmount: () -> Void

    private var days: Double { pantry.daysLeft(for: item) }

    private var urgency: Color {
        if days <= 2 { return Palette.redHot }
        if days <= 7 { return Palette.red.opacity(0.8) }
        return Palette.bone.opacity(0.3)
    }

    private var daysText: String {
        if item.remaining <= 0 { return "out" }
        if days < 1 { return "today" }
        if days < 2 { return "1 day" }
        return "\(Int(days.rounded())) days"
    }

    private var amountText: String {
        "\(fmt(item.remaining)) \(item.unit)"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name.lowercased())
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Palette.bone.opacity(0.9))

                if item.lastOrdered != nil {
                    Text("ordered")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.1)
                        .foregroundStyle(Palette.bone.opacity(0.3))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.steel))
                }

                Spacer()

                Text(daysText)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(urgency)
            }

            HStack(spacing: 12) {
                Text(amountText)
                    .font(.system(size: 24, weight: .heavy).width(.expanded).monospacedDigit())
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .foregroundStyle(Palette.bone)
                    .contentTransition(.numericText())

                Spacer()

                if item.measure == .count {
                    HStack(spacing: 8) {
                        key("arrow.uturn.backward") {
                            haptics.soft()
                            pantry.logUse(item, amount: -1)
                        }
                        key("minus") {
                            haptics.strike()
                            pantry.logUse(item, amount: 1)
                        }
                        // The tap is still there for one or two; this is for
                        // when it was eleven.
                        key("keyboard") {
                            haptics.soft()
                            onTypeAmount()
                        }
                        key("slider.horizontal.3") {
                            haptics.soft()
                            onEdit()
                        }
                    }
                } else if item.measure == .portion {
                    HStack(spacing: 8) {
                        Button {
                            haptics.soft()
                            onTypeAmount()
                        } label: {
                            Text("USED")
                                .font(.system(size: 11, weight: .black))
                                .tracking(1.4)
                                .padding(.horizontal, 16)
                                .frame(height: 38)
                                .background(Capsule().fill(Palette.steel))
                                .overlay(
                                    Capsule().strokeBorder(Palette.red.opacity(0.4), lineWidth: 1)
                                )
                                .foregroundStyle(Palette.bone.opacity(0.8))
                        }
                        .buttonStyle(.plain)

                        key("slider.horizontal.3") {
                            haptics.soft()
                            onEdit()
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Button {
                            haptics.soft()
                            onWeigh()
                        } label: {
                            Text("WEIGH")
                                .font(.system(size: 11, weight: .black))
                                .tracking(1.4)
                                .padding(.horizontal, 16)
                                .frame(height: 38)
                                .background(Capsule().fill(Palette.steel))
                                .overlay(
                                    Capsule().strokeBorder(Palette.red.opacity(0.4), lineWidth: 1)
                                )
                                .foregroundStyle(Palette.bone.opacity(0.8))
                        }
                        .buttonStyle(.plain)

                        key("slider.horizontal.3") {
                            haptics.soft()
                            onEdit()
                        }
                    }
                }
            }

            GeometryReader { geo in
                let span = max(0.0, min(1.0, item.remaining / max(item.fullAmount, 0.001)))
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.bone.opacity(0.08))
                    Capsule()
                        .fill(urgency.opacity(0.75))
                        .frame(width: geo.size.width * span)
                }
            }
            .frame(height: 4)

            HStack {
                Text("\(fmt(pantry.rate(for: item))) \(item.unit) a day")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(Palette.bone.opacity(0.28))

                Spacer()

                let today = pantry.usedToday(item)
                if today > 0 {
                    Text("used \(fmt(today)) today")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.1)
                        .foregroundStyle(Palette.bone.opacity(0.28))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .glassBackdrop(cornerRadius: 28, tint: Palette.bone.opacity(0.06))
    }

    private func key(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .black))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Palette.steel))
                .overlay(Circle().strokeBorder(Palette.red.opacity(0.35), lineWidth: 1))
                .foregroundStyle(Palette.bone.opacity(0.75))
        }
        .buttonStyle(.plain)
    }

    private func fmt(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.05
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value)
    }
}

// MARK: - Weigh prompt

private struct WeighSheet: View {
    let item: GroceryItem
    let pantry: Pantry
    let haptics: GrainHaptics
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()

            VStack(spacing: 20) {
                SheetHeader(title: item.name.lowercased(), showRefresh: false) {} onClose: {
                    dismiss()
                }

                Spacer()

                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 62, weight: .heavy).width(.expanded).monospacedDigit())
                    .foregroundStyle(Palette.bone)
                    .tint(Palette.redHot)

                Text("whole container on the scale, in \(item.unit)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.bone.opacity(0.35))

                Text("empty weighs \(Int(item.tare)) \(item.unit)")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(Palette.bone.opacity(0.25))

                Spacer()

                Button {
                    if let value = Double(text.replacingOccurrences(of: ",", with: ".")) {
                        pantry.setGross(item, gross: value)
                        haptics.commit()
                    }
                    dismiss()
                } label: {
                    Text("SET")
                        .font(.system(size: 15, weight: .black))
                        .tracking(2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Palette.red)
                        )
                        .foregroundStyle(Palette.bone)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
        .onAppear { focused = true }
    }
}

// MARK: - Add and edit

private struct ItemEditor: View {
    let draft: GroceryItem?
    let pantry: Pantry
    let haptics: GrainHaptics
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var measure: GroceryMeasure = .count
    @State private var unit = "units"
    @State private var packSize = ""
    @State private var tare = ""
    @State private var rate = ""
    @State private var remaining = ""

    private var isNew: Bool { draft == nil }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.inkLow, Palette.ink],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                SheetHeader(title: isNew ? "new item" : "edit", showRefresh: false) {} onClose: {
                    dismiss()
                }

                ScrollView {
                    VStack(spacing: 16) {
                        field("name", text: $name, keyboard: .default)

                        measurePicker

                        field(measure == .count ? "unit name, for example eggs" : "amount unit, for example g",
                              text: $unit, keyboard: .default)

                        field(measure == .count ? "how many in a full pack" : "how much in a full pack",
                              text: $packSize, keyboard: .decimalPad)

                        if measure == .weigh {
                            field("empty container weight", text: $tare, keyboard: .decimalPad)
                        }

                        stockField

                        field("rough use per day", text: $rate, keyboard: .decimalPad)

                        if let draft {
                            Button {
                                haptics.commit()
                                pantry.restock(draft)
                                dismiss()
                            } label: {
                                rowButton("refill, I bought a new one", tint: Palette.red)
                            }
                            .buttonStyle(.plain)

                            Button {
                                haptics.soft()
                                pantry.delete(draft)
                                dismiss()
                            } label: {
                                rowButton("remove this item", tint: Palette.steel)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            commit()
                        } label: {
                            Text(isNew ? "ADD" : "SAVE")
                                .font(.system(size: 15, weight: .black))
                                .tracking(2)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(Palette.red)
                                )
                                .foregroundStyle(Palette.bone)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
        .onAppear { prime() }
    }

    private var measurePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("how do you measure it")
                .font(.system(size: 9, weight: .black))
                .tracking(1.4)
                .foregroundStyle(Palette.bone.opacity(0.3))

            ForEach(GroceryMeasure.allCases) { option in
                Button {
                    haptics.soft()
                    let wasDefault = unit == measure.defaultUnit || unit.isEmpty
                    measure = option
                    // Only move the unit if it was still whatever the old mode
                    // suggested; a unit typed by hand is left alone.
                    if wasDefault { unit = option.defaultUnit }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: measure == option
                              ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(
                                measure == option
                                ? Palette.redHot.opacity(0.9)
                                : Palette.bone.opacity(0.25)
                            )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.label)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Palette.bone.opacity(0.8))
                            Text(option.hint)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Palette.bone.opacity(0.3))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackdrop(cornerRadius: 26, tint: Palette.bone.opacity(0.06))
    }

    /// The honest count, typed in whenever the running total has drifted.
    private var stockField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(measure == .count
                 ? "how many are left right now"
                 : "how much is left right now")
                .font(.system(size: 9, weight: .black))
                .tracking(1.4)
                .foregroundStyle(Palette.redHot.opacity(0.65))

            HStack(spacing: 12) {
                TextField("", text: $remaining)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 26, weight: .heavy).width(.expanded).monospacedDigit())
                    .foregroundStyle(Palette.bone)
                    .tint(Palette.redHot)

                Text(unit)
                    .font(.system(size: 12, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(Palette.bone.opacity(0.3))

                Button {
                    haptics.soft()
                    remaining = trim(fullFromFields())
                } label: {
                    Text("FULL")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.3)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Capsule().fill(Palette.steel))
                        .foregroundStyle(Palette.bone.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackdrop(cornerRadius: 26, tint: Palette.red.opacity(0.08))
    }

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .black))
                .tracking(1.4)
                .foregroundStyle(Palette.bone.opacity(0.3))
            TextField("", text: text)
                .keyboardType(keyboard)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Palette.bone)
                .tint(Palette.redHot)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackdrop(cornerRadius: 26, tint: Palette.bone.opacity(0.06))
    }

    private func rowButton(_ label: String, tint: Color) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .black))
            .tracking(1.2)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(tint)
            )
            .foregroundStyle(Palette.bone.opacity(0.85))
    }

    private func prime() {
        guard let draft else {
            remaining = ""
            return
        }
        name = draft.name
        measure = draft.measure
        unit = draft.unit
        packSize = trim(draft.packSize)
        tare = trim(draft.tare)
        rate = trim(draft.startRate)
        remaining = trim(draft.remaining)
    }

    private func trim(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.01
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value)
    }

    private func number(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func fullFromFields() -> Double {
        let pack = max(number(packSize), 0)
        return measure == .weigh ? max(0, pack - number(tare)) : pack
    }

    private func commit() {
        let cleaned = name.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return }

        let pack = max(number(packSize), 0.001)
        let tareValue = measure == .weigh ? number(tare) : 0
        let perDay = max(number(rate), 0.001)
        let full = measure == .weigh ? max(0, pack - tareValue) : pack

        // blank means "however much it was", or a full pack for a new item
        let stock: Double
        if remaining.trimmingCharacters(in: .whitespaces).isEmpty {
            stock = draft?.remaining ?? full
        } else {
            stock = min(max(number(remaining), 0), full)
        }

        if var existing = draft {
            existing.name = cleaned
            existing.measure = measure
            existing.unit = unit.isEmpty ? "units" : unit
            existing.packSize = pack
            existing.tare = tareValue
            existing.startRate = perDay
            existing.remaining = stock
            pantry.upsert(existing)
        } else {
            pantry.upsert(
                GroceryItem(
                    name: cleaned,
                    measure: measure,
                    unit: unit.isEmpty ? "units" : unit,
                    packSize: pack,
                    tare: tareValue,
                    remaining: stock,
                    startRate: perDay
                )
            )
        }

        haptics.commit()
        dismiss()
    }
}

// MARK: - Ordering view

private struct OrderSheet: View {
    let pantry: Pantry
    let haptics: GrainHaptics
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
                SheetHeader(title: "order list", showRefresh: false) {} onClose: {
                    dismiss()
                }

                ScrollView {
                    VStack(spacing: 12) {
                        let low = pantry.runningLow()

                        if low.isEmpty {
                            Text("nothing runs out inside a fortnight")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Palette.bone.opacity(0.4))
                                .padding(.top, 60)
                        } else {
                            Text("check these before you order")
                                .font(.system(size: 9, weight: .black))
                                .tracking(1.5)
                                .foregroundStyle(Palette.bone.opacity(0.3))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 2)

                            ForEach(low) { item in
                                OrderRow(item: item, pantry: pantry, haptics: haptics)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
    }
}

private struct OrderRow: View {
    let item: GroceryItem
    let pantry: Pantry
    let haptics: GrainHaptics

    private var days: Double { pantry.daysLeft(for: item) }
    private var inWindow: Bool { days <= 7 }

    private var verdict: String {
        if item.remaining <= 0 { return "you are out, order it" }
        if days < 1 { return "gone by tonight, order it" }
        if days <= 7 { return "about \(Int(days.rounded())) days left, order it now" }
        return "about \(Int(days.rounded())) days left, you can skip it"
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(inWindow ? Palette.redHot : Palette.bone.opacity(0.18))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name.lowercased())
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Palette.bone.opacity(0.9))
                Text(verdict)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        inWindow ? Palette.redHot.opacity(0.75) : Palette.bone.opacity(0.35)
                    )
            }

            Spacer()

            Button {
                haptics.strike()
                if item.lastOrdered == nil {
                    pantry.markOrdered(item)
                } else {
                    pantry.restock(item)
                }
            } label: {
                Image(systemName: item.lastOrdered == nil ? "cart.badge.plus" : "checkmark")
                    .font(.system(size: 12, weight: .black))
                    .frame(width: 38, height: 38)
                    .background(
                        Circle().fill(item.lastOrdered == nil ? Palette.steel : Palette.red)
                    )
                    .foregroundStyle(Palette.bone.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .glassBackdrop(cornerRadius: 26, tint: Palette.bone.opacity(0.06))
    }
}


/// Typing how much was taken, for a portion item or a big count.
private struct UsedSheet: View {
    let item: GroceryItem
    let pantry: Pantry
    let haptics: GrainHaptics
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var short: Double?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()

            VStack(spacing: 20) {
                SheetHeader(title: item.name.lowercased(), showRefresh: false) {} onClose: {
                    dismiss()
                }

                Spacer()

                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 62, weight: .heavy).width(.expanded).monospacedDigit())
                    .foregroundStyle(Palette.bone)
                    .tint(Palette.redHot)

                Text("how much you just used, in \(item.unit)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.bone.opacity(0.35))

                Text("\(trimmed(item.remaining)) \(item.unit) left")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(Palette.bone.opacity(0.25))

                if let short, short > 0 {
                    Text("only \(trimmed(short)) \(item.unit) short of that — logged what was there")
                        .font(.system(size: 10, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.redHot.opacity(0.8))
                        .padding(.horizontal, 30)
                }

                Spacer()

                Button {
                    commit()
                } label: {
                    Text("LOG IT")
                        .font(.system(size: 15, weight: .black))
                        .tracking(2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Palette.red)
                        )
                        .foregroundStyle(Palette.bone)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
        .onAppear { focused = true }
    }

    private func commit() {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")),
              value > 0
        else {
            dismiss()
            return
        }

        let result = pantry.take(item, amount: value)
        haptics.commit()

        // Say so rather than silently logging less than was asked for.
        if result.short > 0 {
            short = result.short
            text = ""
        } else {
            dismiss()
        }
    }

    private func trimmed(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}


/// Building a meal: a name, and an amount of each item it uses.
private struct MealSheet: View {
    let meal: Meal
    let pantry: Pantry
    let haptics: GrainHaptics
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var amounts: [UUID: String] = [:]
    @State private var loaded = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.inkLow, Palette.ink],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                SheetHeader(title: "meal", showRefresh: false) {} onClose: { dismiss() }

                ScrollView {
                    VStack(spacing: 18) {
                        namePanel
                        itemsPanel
                        buttons
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        name = meal.name
        for portion in meal.portions {
            amounts[portion.itemID] = MealOutcome.trim(portion.amount)
        }
    }

    private var namePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("what you call it out loud")
                .font(.system(size: 9, weight: .black))
                .tracking(1.4)
                .foregroundStyle(Palette.bone.opacity(0.3))

            TextField("lunch", text: $name)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Palette.bone)
                .tint(Palette.redHot)
                .submitLabel(.done)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackdrop(cornerRadius: 26, tint: Palette.bone.opacity(0.06))
    }

    /// Every item, with a blank amount meaning "not in this meal", so adding
    /// and removing is the same gesture as changing an amount.
    private var itemsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("how much of each")
                .font(.system(size: 9, weight: .black))
                .tracking(1.4)
                .foregroundStyle(Palette.bone.opacity(0.3))

            if pantry.items.isEmpty {
                Text("add an item first")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.bone.opacity(0.35))
            }

            ForEach(pantry.items) { item in
                HStack(spacing: 10) {
                    Text(item.name.lowercased())
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.bone.opacity(0.85))

                    Spacer(minLength: 8)

                    TextField("—", text: Binding(
                        get: { amounts[item.id] ?? "" },
                        set: { amounts[item.id] = $0 }
                    ))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 17, weight: .black).monospacedDigit())
                    .foregroundStyle(Palette.bone)
                    .tint(Palette.redHot)
                    .frame(width: 70)

                    Text(item.unit)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Palette.bone.opacity(0.35))
                        .frame(width: 42, alignment: .leading)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackdrop(cornerRadius: 26, tint: Palette.bone.opacity(0.06))
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                save()
            } label: {
                Text("SAVE")
                    .font(.system(size: 15, weight: .black))
                    .tracking(2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Palette.red)
                    )
                    .foregroundStyle(Palette.bone)
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)

            if pantry.meals.contains(where: { $0.id == meal.id }) {
                Button {
                    haptics.commit()
                    pantry.delete(meal)
                    dismiss()
                } label: {
                    Text("delete this meal")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.redHot.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var updated = meal
        updated.name = trimmed
        updated.portions = pantry.items.compactMap { item in
            guard let text = amounts[item.id],
                  let value = Double(text.replacingOccurrences(of: ",", with: ".")),
                  value > 0
            else { return nil }

            // Keep the existing portion's identity where there is one, so
            // editing an amount is an edit rather than a replacement.
            let existing = meal.portions.first { $0.itemID == item.id }
            return MealPortion(
                id: existing?.id ?? UUID(), itemID: item.id, amount: value
            )
        }

        pantry.upsert(updated)
        haptics.commit()
        dismiss()
    }
}
