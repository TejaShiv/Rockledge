//
//  ReminderSheet.swift
//  anynameyoulike
//
//  Created by Tejas Shivaprasad on 10/1/26.
//


import SwiftUI

struct ReminderSheet: View {
    @Binding var isOn: Bool
    let haptics: GrainHaptics
    @Environment(\.dismiss) private var dismiss

    @State private var time = NightlyReminder.timeAsDate
    @State private var note = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.inkLow, Palette.ink],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                SheetHeader(title: "reminder", showRefresh: false) {} onClose: {
                    dismiss()
                }

                Spacer()

                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .frame(maxWidth: 240)

                Text("Steps hakolo Gubaldu...")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.bone.opacity(0.35))
                    .padding(.top, 16)

                Spacer()

                controls
                    .padding(.bottom, 16)

                Text(note)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Palette.bone.opacity(0.4))
                    .frame(minHeight: 18)
                    .padding(.bottom, 34)
            }
        }
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    NightlyReminder.isEnabled = true
                    let ok = await NightlyReminder.apply(at: time)
                    isOn = ok
                    haptics.commit()
                    note = ok
                        ? "set for \(NightlyReminder.timeText) daily"
                        : "allow notifications in Settings"
                }
            } label: {
                Text(isOn ? "UPDATE" : "TURN ON")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(1.6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Capsule().fill(Palette.red))
                    .foregroundStyle(Palette.bone)
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    haptics.soft()
                    Task {
                        let ok = await NightlyReminder.fireTestSoon()
                        note = ok ? "test in 10s, lock the phone" : "allow notifications first"
                    }
                } label: {
                    Text("TEST")
                        .font(.caption2.weight(.black))
                        .tracking(1.4)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            Capsule()
                                .fill(Palette.steel)
                                .overlay(
                                    Capsule().strokeBorder(
                                        Palette.red.opacity(0.3), lineWidth: 1
                                    )
                                )
                        )
                        .foregroundStyle(Palette.bone.opacity(0.7))
                }
                .buttonStyle(.plain)

                if isOn {
                    Button {
                        NightlyReminder.cancel()
                        isOn = false
                        haptics.soft()
                        note = "reminder off"
                    } label: {
                        Text("TURN OFF")
                            .font(.caption2.weight(.black))
                            .tracking(1.4)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                Capsule()
                                    .fill(Palette.steel)
                                    .overlay(
                                        Capsule().strokeBorder(
                                            Palette.bone.opacity(0.15), lineWidth: 1
                                        )
                                    )
                            )
                            .foregroundStyle(Palette.bone.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 34)
    }
}