import SwiftUI

/// Where the token is handed over, and the only screen that ever touches it.
///
/// The token is typed or pasted once, goes straight into the Keychain, and
/// is never read back onto the screen — only the last four characters, which
/// are enough to tell one token from another and no use to anybody else.
struct CanvasSettings: View {
    @Environment(\.dismiss) private var dismiss

    private var canvas: CanvasBoard { Shared.canvas }

    @State private var typed = ""
    @State private var confirmingRemoval = false
    @State private var note: String?

    private var fingerprint: String? { CanvasToken.fingerprint }

    var body: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()

            VStack(spacing: 0) {
                SheetHeader(title: "canvas access", showRefresh: false, onRefresh: {}) {
                    dismiss()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        status
                        field
                        actions
                        explanation
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 6)
                    .padding(.bottom, 40)
                }
            }
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .alert("Remove the Canvas token?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) {
                Task {
                    await canvas.disconnect()
                    note = "Token removed."
                }
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Assignments and their reminders go with it. You can paste a new token any time.")
        }
    }

    // MARK: Pieces

    private var status: some View {
        HStack(spacing: 10) {
            Image(systemName: fingerprint == nil ? "key.slash" : "key.fill")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(fingerprint == nil
                                 ? Palette.bone.opacity(0.3) : CanvasPalette.cloud)

            VStack(alignment: .leading, spacing: 2) {
                Text(fingerprint == nil ? "Not connected" : "Connected")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Palette.bone.opacity(0.85))

                Text(fingerprint ?? "No token saved")
                    .font(.system(size: 11, weight: .bold).monospaced())
                    .foregroundStyle(Palette.bone.opacity(0.35))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.steel.opacity(0.6))
        )
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(fingerprint == nil ? "paste your token" : "paste a replacement")
                .font(.system(size: 9, weight: .black))
                .tracking(1.6)
                .foregroundStyle(Palette.bone.opacity(0.3))

            SecureField("", text: $typed)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, weight: .bold).monospaced())
                .foregroundStyle(Palette.bone)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Palette.steel.opacity(0.6))
                )

            if let note {
                Text(note)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.bone.opacity(0.45))
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                save()
            } label: {
                Text(fingerprint == nil ? "Connect" : "Replace token")
                    .font(.system(size: 14, weight: .black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(CanvasPalette.cloud.opacity(
                                typed.trimmed.isEmpty ? 0.2 : 0.85
                            ))
                    )
                    .foregroundStyle(Palette.ink)
            }
            .buttonStyle(.plain)
            .disabled(typed.trimmed.isEmpty)

            if fingerprint != nil {
                Button {
                    confirmingRemoval = true
                } label: {
                    Text("Remove token")
                        .font(.system(size: 13, weight: .black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Palette.redHot.opacity(0.14))
                        )
                        .foregroundStyle(Palette.redHot.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("where it is kept")
                .font(.system(size: 9, weight: .black))
                .tracking(1.6)
                .foregroundStyle(Palette.bone.opacity(0.3))

            Text("""
            The token goes into the iOS Keychain and nowhere else — not into \
            the app's settings, not into kalla.json, and not into the backup \
            you export. It never leaves the phone except as an Authorization \
            header to \(CanvasAPI.host).
            """)
            .font(.system(size: 12, weight: .medium))
            .lineSpacing(3)
            .foregroundStyle(Palette.bone.opacity(0.4))

            Text("""
            Make one in Canvas under Account → Settings → New Access Token. \
            If assignments stop loading, the token has expired or been \
            revoked — paste a fresh one above.
            """)
            .font(.system(size: 12, weight: .medium))
            .lineSpacing(3)
            .foregroundStyle(Palette.bone.opacity(0.4))
        }
        .padding(.top, 4)
    }

    private func save() {
        let token = typed.trimmed
        guard !token.isEmpty else { return }

        guard canvas.connect(token) else {
            note = "The Keychain refused to store that."
            return
        }

        typed = ""
        note = "Saved. Checking it now…"
        Shared.haptics.commit()

        Task {
            await canvas.refresh()
            note = canvas.failure?.message ?? "Working."
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
