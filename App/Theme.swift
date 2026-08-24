import SwiftUI
import AuthenticationServices

// MARK: - Brand palette
//
// Coordinated with the app logo (teal → green). Per Apple HIG the app uses a
// single accent (brandPrimary) for interactivity, keeps green/red purely as
// income/expense *signals* (see `moneyIn`/`moneyOut` in Components), and lets
// neutrals + content dominate. Light-mode tones are deep enough that white text
// sits ≥ 4.5:1 on the brand gradient; dark-mode tones brighten to stay vivid.

extension Color {
    /// Primary brand color + app-wide accent/tint. Deep teal in light mode
    /// (high contrast on white), bright teal in dark mode.
    static let brandPrimary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.82, blue: 0.75, alpha: 1)   // #33D1BF
            : UIColor(red: 0.043, green: 0.443, blue: 0.404, alpha: 1) // #0B7167
    })

    /// Secondary brand color — the green end of the logo gradient.
    static let brandSecondary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.27, green: 0.85, blue: 0.54, alpha: 1)   // #45D98A
            : UIColor(red: 0.071, green: 0.522, blue: 0.294, alpha: 1) // #12854B
    })

    /// The logo's teal→green diagonal (adaptive brand tones).
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [.brandPrimary, .brandSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Hero gradient — intentionally the DEEP tones in *both* light and dark, so
    /// white foreground text always clears 4.5:1. (The adaptive brand tones
    /// brighten in dark mode for use as an accent on dark surfaces, which is too
    /// light behind white text.)
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.043, green: 0.443, blue: 0.404), // deep teal  #0B7167
                Color(red: 0.071, green: 0.522, blue: 0.294)  // deep green #12854B
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Balance hero

/// The branded "balance card" that anchors Home — the fintech pattern that
/// replaces a plain list header. Spent this month is the headline; income sits
/// beneath as a secondary figure. White foreground on the deep brand gradient.
struct BalanceHeroCard: View {
    let spentTitle: LocalizedStringKey
    let spent: String
    let incomeTitle: LocalizedStringKey
    let income: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(spentTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                Text(spent)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            Divider().overlay(.white.opacity(0.35))

            // At AX sizes the income label + amount don't fit side-by-side;
            // stack them vertically so neither truncates.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.left.circle.fill")
                            .foregroundStyle(.white.opacity(0.9))
                        Text(incomeTitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Text(income)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.left.circle.fill")
                        .foregroundStyle(.white.opacity(0.9))
                    Text(incomeTitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text(income)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .brandPrimary.opacity(0.25), radius: 10, x: 0, y: 6)
        // One VoiceOver element: "Spent this month, ₩…, income this month, ₩…".
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty state

/// Branded empty state: a large brand-tinted glyph with a title + hint. Used by
/// the list screens so a fresh install feels designed rather than blank.
struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Color.brandPrimary)
                .symbolRenderingMode(.hierarchical)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Backup prompt (Home discoverability card)

/// A dismissible card on Home that tells first-time users their data is local
/// and offers one-tap Sign in with Apple to enable backup/sync. Auto-hidden
/// once signed in; dismissal is remembered by the caller.
struct BackupPromptCard: View {
    @ObservedObject var signIn: SignInManager
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Back up your data", systemImage: "icloud.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandPrimary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            Text("Your expenses are saved on this device only. Sign in with Apple to back them up and sync across your devices.")
                .font(.caption)
                .foregroundStyle(.secondary)
            SignInWithAppleButton(.signIn) { request in
                signIn.configure(request)
            } onCompletion: { result in
                signIn.handle(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 40)
        }
        .padding()
        .background(Color.brandPrimary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview("Balance Hero — Light") {
    BalanceHeroCard(
        spentTitle: "Spent this month", spent: "₩1,240,000",
        incomeTitle: "Income this month", income: "₩3,000,000"
    )
    .padding()
}

#Preview("Balance Hero — Dark") {
    BalanceHeroCard(
        spentTitle: "Spent this month", spent: "₩1,240,000",
        incomeTitle: "Income this month", income: "₩3,000,000"
    )
    .padding()
    .preferredColorScheme(.dark)
}
