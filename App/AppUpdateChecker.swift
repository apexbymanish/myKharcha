import UIKit
import SwiftUI

/// Checks for app updates. The Remote Config implementation is disabled until
/// FirebaseRemoteConfig is linked to the Kharcha target in Xcode Build Phases.
/// To re-enable: add FirebaseRemoteConfig to Link Binary With Libraries, then
/// restore the FirebaseRemoteConfig import and check() body from git history
/// (commit f3622e0).
@MainActor
final class AppUpdateChecker: ObservableObject {

    enum UpdateKind {
        case none
        case optional(message: String)
        case mandatory(message: String)
    }

    @Published private(set) var kind: UpdateKind = .none

    private static let storeURL = URL(string: "https://apps.apple.com/app/id6804884920")!

    func check() async {
        // Remote Config check disabled — see comment above.
    }

    func openAppStore() {
        UIApplication.shared.open(Self.storeURL)
    }
}

// MARK: — Blocking screen for mandatory updates

struct MandatoryUpdateView: View {
    let message: String
    let onUpdate: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.brandPrimary)
            Text("Update Required")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: onUpdate) {
                Text("Update Now")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.brandPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .interactiveDismissDisabled(true)
    }
}
