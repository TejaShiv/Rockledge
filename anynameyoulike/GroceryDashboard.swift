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
            // "250g" reads fine, "4slices" does not: a symbol joins the
            // number, a word needs a space.
            let gap = item.unit.count <= 2 ? "" : " "
            return "\(MealOutcome.trim(portion.amount))\(gap)\(item.unit) \(item.name.lowercased())"
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
