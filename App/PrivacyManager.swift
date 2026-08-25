import LocalAuthentication
import SwiftUI

/// Session-scoped privacy gate. Financial amounts are hidden by default and
/// revealed only after a successful biometric or passcode challenge.
/// Automatically locks when the app moves to the background.
@MainActor
final class PrivacyManager: ObservableObject {
    @Published private(set) var isRevealed = false

    func lock() { isRevealed = false }

    func requestReveal() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Device has no passcode — reveal without auth.
            isRevealed = true
            return
        }
        do {
            isRevealed = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Reveal your financial details")
            )
        } catch {
            isRevealed = false
        }
    }
}
