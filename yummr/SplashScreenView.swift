//
//  SplashScreenView 2.swift
//  yummr
//
//  Created by kuba woahz on 9/15/25.
//


import SwiftUI

struct SplashScreenView: View {
    @State private var fadeIn = false

    var body: some View {
        ZStack {
            Color(UIColor.systemGray6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Savor.")
                    .font(.largeTitle.bold())
                    .foregroundColor(.black)
                    .opacity(fadeIn ? 1 : 0.3)
                    .scaleEffect(fadeIn ? 1 : 0.95)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                               value: fadeIn)

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.black)
            }
        }
        .onAppear {
            fadeIn = true
        }
    }
}
