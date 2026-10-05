import SwiftUI

// MARK: - Health style door, one hero number

struct DoorCard: View {
    let icon: String
    let title: String
    let value: String
    let caption: String
    var tint: Color = Palette.bone.opacity(0.45)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DoorHeader(icon: icon, title: title, tint: tint)

            Spacer()

            Text(value)
                .font(.system(size: 44, weight: .heavy).width(.expanded).monospacedDigit())
                .minimumScaleFactor(0.35)
                .lineLimit(1)
                .foregroundStyle(Palette.bone)
                .contentTransition(.numericText())
                .shadow(color: Color.black.opacity(0.8), radius: 2, y: 2)

            Text(caption)
                .font(.system(size: 9, weight: .black))
                .tracking(1.4)
                .foregroundStyle(Palette.bone.opacity(0.3))
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 150)
        .glassBackdrop(cornerRadius: 32, tint: Palette.bone.opacity(0.06))
        // Without this only the text inside is tappable: the glass itself
        // is not hit-testable, so taps on the empty part of a card are lost.
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

// MARK: - Grocery door, a short status list

struct StockLine: Identifiable {
    let id: UUID
    let name: String
    let days: String
    let urgency: Color
}

struct GroceryDoorCard: View {
    let lines: [StockLine]
    let emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DoorHeader(
                icon: "basket.fill",
                title: "groceries",
                tint: Palette.bone.opacity(0.45)
            )

            Spacer(minLength: 10)

            if lines.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.bone.opacity(0.35))
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 9) {
                    ForEach(lines) { line in
                        HStack(spacing: 11) {
                            Circle()
                                .fill(line.urgency)
                                .frame(width: 7, height: 7)

                            Text(line.name)
                                .font(.system(size: 15, weight: .bold))
                                .lineLimit(1)
                                .foregroundStyle(Palette.bone.opacity(0.85))

                            Spacer(minLength: 8)

                            Text(line.days)
                                .font(.system(size: 13, weight: .black).monospacedDigit())
                                .foregroundStyle(line.urgency)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 150)
        .glassBackdrop(cornerRadius: 32, tint: Palette.bone.opacity(0.06))
        // Without this only the text inside is tappable: the glass itself
        // is not hit-testable, so taps on the empty part of a card are lost.
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

// MARK: - MBTA door, the next bus each way home

struct TransitLine: Identifiable {
    let id: String
    let route: String
    let destination: String
    let minutes: String
}

struct TransitDoorCard: View {
    let lines: [TransitLine]
    let emptyMessage: String
    /// Set only when the times on show are older than the last attempt.
    let staleNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DoorHeader(
                icon: "bus.fill",
                title: "mbta",
                tint: Palette.redHot.opacity(0.75)
            )

            Spacer(minLength: 10)

            if lines.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.bone.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 9) {
                    ForEach(lines) { line in
                        HStack(spacing: 11) {
                            Text(line.route)
                                .font(.system(size: 12, weight: .black).monospacedDigit())
                                .foregroundStyle(Palette.bone.opacity(0.9))
                                .frame(minWidth: 26)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Palette.red.opacity(0.8)))

                            Text(line.destination)
                                .font(.system(size: 15, weight: .bold))
                                .lineLimit(1)
                                .foregroundStyle(Palette.bone.opacity(0.85))

                            Spacer(minLength: 8)

                            Text(line.minutes)
                                .font(.system(size: 13, weight: .black).monospacedDigit())
                                .foregroundStyle(Palette.bone.opacity(0.85))
                        }
                    }
                }
            }

            if let staleNote {
                Text(staleNote)
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(Palette.redHot.opacity(0.6))
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 150)
        .glassBackdrop(cornerRadius: 32, tint: Palette.bone.opacity(0.06))
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

// MARK: - Shared top row

private struct DoorHeader: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11, weight: .black))
                .tracking(2)
                .foregroundStyle(Palette.bone.opacity(0.4))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Palette.bone.opacity(0.22))
        }
    }
}

// MARK: - Back chevron and title for pushed screens

struct ScreenHeader: View {
    let title: String
    var trailing: AnyView? = nil
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.black))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Palette.bone.opacity(0.6))
                    .background(Circle().fill(Palette.steel))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(.caption.weight(.black))
                .tracking(2)
                .foregroundStyle(Palette.bone.opacity(0.5))

            Spacer()

            if let trailing {
                trailing
            } else {
                Color.clear.frame(width: 34, height: 34)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
