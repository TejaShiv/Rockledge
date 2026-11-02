import SwiftUI

// MARK: - A colour per class

/// Classes are told apart by colour before they are read, so the colour has
/// to be the same every time the app opens. Named subjects get a chosen
/// colour; everything else gets one picked from the code itself, which is
/// stable in a way that `hashValue` is not — that is seeded per process and
/// would repaint the screen on every launch.
nonisolated enum CanvasPalette {

    static let web = Color(red: 0.66, green: 0.47, blue: 0.99)      // CS5610
    static let cloud = Color(red: 0.33, green: 0.64, blue: 0.99)    // CS6620

    private static let spare: [Color] = [
        Color(red: 0.26, green: 0.80, blue: 0.69),      // teal
        Color(red: 0.99, green: 0.65, blue: 0.29),      // amber
        Color(red: 0.98, green: 0.44, blue: 0.62),      // rose
        Color(red: 0.55, green: 0.84, blue: 0.42),      // green
        Color(red: 0.95, green: 0.84, blue: 0.35),      // straw
        Color(red: 0.56, green: 0.60, blue: 0.98),      // periwinkle
    ]

    static func tint(for code: String) -> Color {
        switch code {
        case "CS5610": return web
        case "CS6620": return cloud
        default:
            let seed = code.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
            return spare[seed % spare.count]
        }
    }
}

nonisolated extension CanvasClass {
    var tint: Color { CanvasPalette.tint(for: code) }
}

// MARK: - The door

/// The fourth card. Says one thing: what is due next, and roughly how much
/// is behind it.
struct CanvasDoorCard: View {
    let subject: CanvasClass?
    let next: CanvasAssignment?
    let dueThisWeek: Int
    /// Set when there is no token, or the token stopped working.
    let problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Spacer(minLength: 10)

            if let problem {
                Text(problem)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.bone.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else if let next, let subject {
                assignment(next, in: subject)
            } else {
                Text("Nothing due")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.bone.opacity(0.35))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 150)
        .glassBackdrop(cornerRadius: 32, tint: Palette.bone.opacity(0.06))
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var header: some View {
        HStack {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(subject?.tint ?? Palette.bone.opacity(0.45))
            Text("canvas")
                .font(.system(size: 11, weight: .black))
                .tracking(2)
                .foregroundStyle(Palette.bone.opacity(0.4))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Palette.bone.opacity(0.22))
        }
    }

    private func assignment(_ item: CanvasAssignment,
                            in subject: CanvasClass) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle()
                    .fill(subject.tint)
                    .frame(width: 7, height: 7)

                Text(subject.title.lowercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.4)
                    .lineLimit(1)
                    .foregroundStyle(subject.tint.opacity(0.85))
            }

            Text(item.name)
                .font(.system(size: 17, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Palette.bone)
                .padding(.top, 5)

            Spacer(minLength: 4)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(CanvasDue.phrase(for: item.dueAt))
                    .font(.system(size: 13, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(subject.tint)

                Spacer(minLength: 4)

                if dueThisWeek > 1 {
                    Text("\(dueThisWeek) this week")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(Palette.bone.opacity(0.3))
                }
            }
        }
    }
}
