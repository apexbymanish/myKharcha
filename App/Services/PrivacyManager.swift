import SwiftUI

/// Shoulder-surfing guard: hides financial amounts until the user explicitly
/// reveals them. Simple toggle — no biometric required. Stays revealed through
/// background/foreground cycles; resets to hidden on each fresh app launch.
@MainActor
final class PrivacyManager: ObservableObject {
    @Published private(set) var isRevealed = false

    func toggle() { isRevealed.toggle() }
}
