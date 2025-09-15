import SwiftUI

struct SplashScreenView: View {
    @State private var fadeIn = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.orange, Color.pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Savor. Cook more.")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                    .opacity(fadeIn ? 1 : 0.3)
                    .scaleEffect(fadeIn ? 1 : 0.95)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: fadeIn)

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
        }
        .onAppear {
            fadeIn = true
        }
    }
}
