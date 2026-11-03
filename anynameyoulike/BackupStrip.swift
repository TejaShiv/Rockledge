import SwiftUI

/// How long since a copy of the document left the phone.
///
/// This used to raise the share sheet itself on every launch until you
/// completed an export — on the reasoning that the cost of forgetting was
/// losing everything. That reasoning no longer holds: the Mac now pulls
/// `kalla.json` off the phone on every auto-rebuild run, validates it and
/// keeps thirty copies, so the data is backed up whether or not you ever
/// tap anything.
///
/// What is left is worth saying but not worth blocking the app for, so it
/// is a line rather than a sheet.
struct BackupStrip: View {
    /// Raises the export sheet. The strip only offers; it never insists.
    let onExport: () -> Void

    private var lastExport: Date? { Backup.lastExport }

    private var isOverdue: Bool {
        Backup.isExportOverdue(
            lastExport: lastExport,
            hasContent: Backup.Summary(Store.document).isWorthKeeping
        )
    }

    var body: some View {
        if isOverdue {
            Button(action: onExport) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.document")
                        .font(.system(size: 10, weight: .black))

                    Text(wording)
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)

                    Text("export")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(Palette.bone.opacity(0.55))
                }
                .foregroundStyle(Palette.bone.opacity(0.4))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.bone.opacity(0.05))
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var wording: String {
        guard let lastExport else { return "never exported off this phone" }

        let days = Calendar.current.dateComponents(
            [.day], from: lastExport, to: Date()
        ).day ?? 0

        return days <= 1
            ? "last export was yesterday"
            : "last export was \(days) days ago"
    }
}
