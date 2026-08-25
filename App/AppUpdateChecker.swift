import FirebaseRemoteConfig
import UIKit
import SwiftUI

/// Checks Firebase Remote Config on launch and determines whether this build
/// needs an update. Does not block the app if the network is unavailable —
/// failures are silent and treated as "no update required".
///
/// Remote Config keys to set in the Firebase Console:
///   ios_min_version       — oldest version still allowed (e.g. "1.2.0")
///   ios_latest_version    — current App Store version (e.g. "1.3.0")
///   ios_update_message    — shown for optional updates
///   ios_force_message     — shown for mandatory updates
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
        let rc = RemoteConfig.remoteConfig()

        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600
        rc.configSettings = settings

        rc.setDefaults([
            "ios_min_version":    "" as NSObject,
            "ios_latest_version": "" as NSObject,
            "ios_update_message": "A new version of Kharcha is available with improvements and fixes." as NSObject,
            "ios_force_message":  "This version of Kharcha is no longer supported. Please update to continue." as NSObject,
        ])

        do {
            try await rc.fetch()
            try await rc.activate()
        } catch {
            return
        }

        guard let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }

        let minVersion    = rc["ios_min_version"].stringValue ?? ""
        let latestVersion = rc["ios_latest_version"].stringValue ?? ""

        if !minVersion.isEmpty, isOlder(current, than: minVersion) {
            let msg = rc["ios_force_message"].stringValue ?? ""
            kind = .mandatory(message: msg)
        } else if !latestVersion.isEmpty, isOlder(current, than: latestVersion) {
            let msg = rc["ios_update_message"].stringValue ?? ""
            kind = .optional(message: msg)
        }
    }

    func openAppStore() {
        UIApplication.shared.open(Self.storeURL)
    }

    private func isOlder(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedAscending
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
