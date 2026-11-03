import SwiftUI

/// Adding an item and editing one: the three measurement modes, the
/// pack size, and what is left right now.

// MARK: - Add and edit

struct ItemEditor: View {
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
            // Not capped at a pack: a full 12 and 3 loose is 15, and that is
            // a real answer. Only below zero is impossible.
            stock = max(number(remaining), 0)
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
