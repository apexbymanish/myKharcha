import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconScale: CGFloat = 0.3
    @State private var iconOpacity: Double = 0
    @State private var iconRotation: Double = 0
    @State private var nameOpacity: Double = 0
    @State private var nameOffsetY: CGFloat = 10

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.443, blue: 0.404)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image("AppLogo")
                    .resizable()
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
                    .rotationEffect(.degrees(iconRotation))

                VStack(spacing: 5) {
                    Text("Paisa Khoi?")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Expense Tracker")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .opacity(nameOpacity)
                .offset(y: nameOffsetY)
            }
        }
        .accessibilityHidden(true)
        .onAppear { startAnimation() }
    }

    private func startAnimation() {
        // Pop in
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.55)) {
            iconScale = 1.0
            iconOpacity = 1
        }
        // Look left
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { iconRotation = -14 }
        }
        // Look right
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { iconRotation = 14 }
        }
        // Look left again (still searching)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { iconRotation = -8 }
        }
        // Settle centre — gave up / ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6)) { iconRotation = 0 }
        }
        // Name slides up
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7)) {
                nameOpacity = 1
                nameOffsetY = 0
            }
        }
    }
}

#Preview {
    SplashView()
}
