import SwiftUI

/// The sheets the grocery screen raises: reordering the list, logging
/// what was used, and logging a whole meal.

// MARK: - Ordering view

struct OrderSheet: View {
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
struct UsedSheet: View {
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
struct MealSheet: View {
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
