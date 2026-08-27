import SwiftUI

/// Full-screen brand splash shown for ~0.8 s on every cold launch.
/// Matches the system launch screen color exactly so the transition is seamless.
/// Fades out with a 0.3 s ease-out once the timer fires.
struct SplashView: View {
    // Wallet
    @State private var walletScale: CGFloat = 0.1
    @State private var walletOffsetY: CGFloat = 40
    @State private var walletOpacity: Double = 0

    // Eyes — sit just above the wallet, scan left/right like the icon character
    @State private var eyesOpacity: Double = 0
    @State private var eyesOffsetX: CGFloat = 0
    @State private var eyesScale: CGFloat = 0.5

    // Question mark
    @State private var questionOpacity: Double = 0
    @State private var questionBob: CGFloat = 0
    @State private var questionScale: CGFloat = 0.3

    // Money flying away
    @State private var money: [MoneyParticle] = MoneyParticle.initial()

    // App name
    @State private var nameOpacity: Double = 0
    @State private var nameOffsetY: CGFloat = 12

    var body: some View {
        ZStack {
            // Exact match to LaunchBackground asset (#0B7167 deep teal).
            Color(red: 0.043, green: 0.443, blue: 0.404)
                .ignoresSafeArea()

            // Money particles scattering behind everything
            ForEach(money) { p in
                Text(p.emoji)
                    .font(.system(size: p.size))
                    .offset(x: p.x, y: p.y)
                    .opacity(p.opacity)
                    .rotationEffect(.degrees(p.rotation))
            }

            VStack(spacing: 0) {
                // Character layer: eyes above wallet
                ZStack(alignment: .top) {
                    // Eyes float above the wallet (mirroring icon layout)
                    Text("👀")
                        .font(.system(size: 36))
                        .offset(x: eyesOffsetX, y: -16)
                        .scaleEffect(eyesScale)
                        .opacity(eyesOpacity)
                        .zIndex(1)

                    // Wallet icon
                    Image("AppLogo")
                        .resizable()
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
                        .scaleEffect(walletScale)
                        .offset(y: walletOffsetY)
                        .opacity(walletOpacity)
                        .zIndex(0)

                    // Question mark — top-right, like in the icon
                    Text("❓")
                        .font(.system(size: 28))
                        .offset(x: 36, y: -24)
                        .scaleEffect(questionScale)
                        .opacity(questionOpacity)
                        .offset(y: questionBob)
                        .zIndex(2)
                }
                .frame(width: 140, height: 120)

                Spacer().frame(height: 24)

                // App name
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
        // 1. Eyes peek in first — scanning left
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            eyesOpacity = 1
            eyesScale = 1.0
            eyesOffsetX = -18   // look left
        }

        // 2. Eyes scan right
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.3)) {
                eyesOffsetX = 18  // look right
            }
        }

        // 3. Eyes look back centre — wallet pops up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.2)) {
                eyesOffsetX = 0   // back to centre
            }
            // Wallet springs up
            withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) {
                walletScale = 1.0
                walletOffsetY = 0
                walletOpacity = 1
            }
        }

        // 4. Question mark pops in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) {
                questionOpacity = 1
                questionScale = 1.0
            }
            // Bob continuously
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                questionBob = -6
            }
        }

        // 5. Money scatters away (like it escaped)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            for i in money.indices {
                let delay = Double(i) * 0.07
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeOut(duration: 0.65)) {
                        money[i].x += money[i].scatterX
                        money[i].y += money[i].scatterY
                        money[i].opacity = 0
                        money[i].rotation += money[i].scatterSpin
                    }
                }
            }
        }

        // 6. Eyes do a quick surprised widen (scale pulse)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
                eyesScale = 1.25
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    eyesScale = 1.0
                }
            }
        }

        // 7. Name slides up
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                nameOpacity = 1
                nameOffsetY = 0
            }
        }
    }
}

// MARK: - Money particle

private struct MoneyParticle: Identifiable {
    let id = UUID()
    var emoji: String
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
    var rotation: Double
    var scatterX: CGFloat
    var scatterY: CGFloat
    var scatterSpin: Double

    static func initial() -> [MoneyParticle] {
        [
            MoneyParticle(emoji: "💸", x: -70, y:  20, size: 22, opacity: 0.9, rotation:   0, scatterX: -60, scatterY: -50, scatterSpin:  40),
            MoneyParticle(emoji: "💰", x:  65, y:  10, size: 18, opacity: 0.8, rotation:  10, scatterX:  55, scatterY: -60, scatterSpin: -35),
            MoneyParticle(emoji: "💸", x: -30, y:  55, size: 20, opacity: 0.85, rotation: -8, scatterX: -40, scatterY:  55, scatterSpin:  50),
            MoneyParticle(emoji: "💵", x:  45, y:  60, size: 16, opacity: 0.75, rotation:  5, scatterX:  50, scatterY:  50, scatterSpin: -45),
            MoneyParticle(emoji: "💸", x:   5, y: -30, size: 24, opacity: 0.9, rotation:  -5, scatterX:  10, scatterY: -70, scatterSpin:  30),
        ]
    }
}

#Preview {
    SplashView()
}
