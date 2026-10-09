import SwiftUI
import UniformTypeIdentifiers

struct BackupSheet: View {
    let haptics: GrainHaptics
    /// Called after the document has actually been replaced, so the screens
    /// behind this one can re-read it.
    let onRestored: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var exported: URL?
    @State private var picking = false
    @State private var pending: (document: Store.Document, summary: Backup.Summary)?
    @State private var fault: Backup.Fault?

    private var current: Backup.Summary { Backup.Summary(Store.document) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.inkLow, Palette.ink],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                SheetHeader(title: "backup", showRefresh: false) {} onClose: {
                    dismiss()
                }

                ScrollView {
                    VStack(spacing: 18) {
                        whyPanel
                        exportPanel
                        importPanel
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
        .fileImporter(
            isPresented: $picking,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let document = try Backup.inspect(url)
                    pending = (document, Backup.Summary(document))
                } catch let problem as Backup.Fault {
                    fault = problem
                } catch {
                    fault = .unreadable
                }
            case .failure:
                fault = .unreadable
            }
        }
        .alert(
            "Replace everything?",
            isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            ),
            presenting: pending
        ) { incoming in
            Button("Replace", role: .destructive) {
                Backup.restore(incoming.document)
                haptics.commit()
                onRestored()
                dismiss()
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { incoming in
            Text(replaceWarning(for: incoming.summary))
        }
        .alert(
            "Could not import",
            isPresented: Binding(
                get: { fault != nil },
                set: { if !$0 { fault = nil } }
            ),
            presenting: fault
        ) { _ in
            Button("OK", role: .cancel) { fault = nil }
        } message: { problem in
            Text(problem.errorDescription ?? "That file could not be read.")
        }
    }

    private func replaceWarning(for incoming: Backup.Summary) -> String {
        let now = current
        var text = "This backup holds \(incoming.lines.joined(separator: ", "))."
        if let saved = incoming.savedAt {
            text += "\nSaved \(Self.stamp.string(from: saved))."
        }
        text += "\n\nIt will replace what is here now: "
            + now.lines.joined(separator: ", ")
            + ". This cannot be undone."
        return text
    }

    // MARK: Panels

    private var whyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("everything in one file")
                .font(.system(size: 9, weight: .black))
                .tracking(1.6)
                .foregroundStyle(Palette.bone.opacity(0.3))

            Text("""
                Groceries, the trash rota, the step ledger and the bus stop all \
                live in kalla.json. Re-signing the app gives it a new container \
                and the old file goes with the old one, so keep a copy somewhere \
                that is not the phone.
                """)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.bone.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                ForEach(current.lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(Palette.bone.opacity(0.35))
                }
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackdrop(cornerRadius: 28, tint: Palette.bone.opacity(0.06))
    }

    private var exportPanel: some View {
        VStack(spacing: 10) {
            if let exported {
                ShareLink(item: exported) {
                    actionLabel("export a copy", icon: "square.and.arrow.up", filled: true)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { haptics.soft() })
            } else {
                Button {
                    haptics.soft()
                    exported = try? Backup.exportFile()
                } label: {
                    actionLabel("export a copy", icon: "square.and.arrow.up", filled: true)
                }
                .buttonStyle(.plain)
            }

            Text(exported == nil
                 ? "writes a dated copy, then opens the share sheet"
                 : "ready — send it to iCloud Drive or mail it to yourself")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.bone.opacity(0.3))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassBackdrop(cornerRadius: 28, tint: Palette.bone.opacity(0.06))
        .task {
            // Prepared up front so the button is one tap, not two.
            exported = try? Backup.exportFile()
        }
    }

    private var importPanel: some View {
        VStack(spacing: 10) {
            Button {
                haptics.soft()
                picking = true
            } label: {
                actionLabel("import a backup", icon: "square.and.arrow.down", filled: false)
            }
            .buttonStyle(.plain)

            Text("checked before anything is replaced, and you get the last word")
                .font(.system(size: 10, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.bone.opacity(0.3))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassBackdrop(cornerRadius: 28, tint: Palette.bone.opacity(0.06))
    }

    private func actionLabel(_ title: String, icon: String, filled: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))
            Text(title)
                .font(.system(size: 13, weight: .black))
                .tracking(1.4)
        }
        .foregroundStyle(filled ? Palette.bone : Palette.bone.opacity(0.75))
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background {
            if filled {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Palette.red)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        Palette.bone.opacity(0.14),
                        style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
                    )
            }
        }
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
