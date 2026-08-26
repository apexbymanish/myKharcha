import SwiftUI

/// Full-screen brand splash shown for ~0.8 s on every cold launch.
/// Matches the system launch screen color exactly so the transition is seamless.
/// Fades out with a 0.3 s ease-out once the timer fires.
struct SplashView: View {
    var body: some View {
        ZStack {
            // Exact match to LaunchBackground asset (#0B7167 deep teal).
            Color(red: 0.043, green: 0.443, blue: 0.404)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Monogram circle — consistent with the avatar style used in ProfileView.
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 96, height: 96)
                    Text("K")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 4) {
                    Text("jeb kharcha")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("your spending, simplified")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
        .accessibilityHidden(true)   // VoiceOver skips the splash entirely.
    }
}

#Preview {
    SplashView()
}
