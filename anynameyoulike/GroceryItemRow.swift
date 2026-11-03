import SwiftUI

/// One line in the grocery list, and the weigh prompt it raises.
///
/// Split out of GroceryDashboard, which had grown to the point where
/// finding the row took longer than changing it.

// MARK: - One item

struct ItemRow: View {
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

    /// How much there is beyond one full pack.
    private var overflow: Double {
        max(0, item.remaining - item.fullAmount)
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

                if overflow > 0 {
                    Text("+\(fmt(overflow))")
                        .font(.system(size: 10, weight: .black).monospacedDigit())
                        .tracking(0.8)
                        .foregroundStyle(Palette.bone.opacity(0.9))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.red.opacity(0.75)))
                }

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

            // The bar answers "how much of a pack is left", so it is capped
            // at a pack rather than rescaled. Rescaling would make a full bar
            // mean something different at every amount — 15 of 15 and 13 of
            // 13 would both look full — and the proportion is the only thing
            // a four point line can say. Being over a pack is said in words
            // instead, beside the number, which already reads true.
            GeometryReader { geo in
                let span = max(0.0, min(1.0, item.remaining / max(item.fullAmount, 0.001)))
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.bone.opacity(0.08))
                    Capsule()
                        .fill(urgency.opacity(overflow > 0 ? 1 : 0.75))
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

struct WeighSheet: View {
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
