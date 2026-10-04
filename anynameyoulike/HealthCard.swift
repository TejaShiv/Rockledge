//
//  HealthCard.swift
//  anynameyoulike
//
//  Created by Tejas Shivaprasad on 10/1/26.
//


import SwiftUI

/// Uniform card shell so all three match exactly.
struct HealthCard<Content: View>: View {
    let icon: String
    let caption: String
    let iconTint: Color
    @ViewBuilder let content: () -> Content

    static var height: CGFloat { 136 }

    var body: some View {
        ZStack {
            content()

            VStack {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(iconTint)
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    Text(caption)
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.4)
                        .foregroundStyle(Palette.bone.opacity(0.3))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .glassBackdrop(cornerRadius: 32, tint: Palette.bone.opacity(0.06))
    }
}