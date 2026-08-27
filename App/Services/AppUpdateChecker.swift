import UIKit
import SwiftUI
import FirebaseFirestore

// MARK: - How to configure (Firebase Console → Firestore)
//
// Create document:  config/appUpdate
// Fields:
//   min_ios_version      (String)  "2.1.0"  → mandatory update if installed < this
//   latest_ios_version   (String)  "2.2.0"  → optional  update if installed < this
//   mandatory_message    (String)  custom text, or leave blank for the default below
//   optional_message     (String)  custom text, or leave blank for the default below
//
// Firestore rules — add a public read for this one document:
//   match /config/appUpdate {
//     allow read: if true;
//   }
//
// Leave min_ios_version / latest_ios_version empty ("") to suppress all update banners.

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
        do {
            let doc = try await Firestore.firestore()
                .collection("config")
                .document("appUpdate")
                .getDocument()

            guard doc.exists, let data = doc.data() else { return }

            let current = Bundle.main.shortVersionString
            let minVer  = data["min_ios_version"]    as? String ?? ""
            let latVer  = data["latest_ios_version"] as? String ?? ""
            let mandMsg = data["mandatory_message"]  as? String ?? "Please update Kharcha to continue."
            let optMsg  = data["optional_message"]   as? String ?? "A new version of Kharcha is available."

            if !minVer.isEmpty, current.versionLessThan(minVer) {
                kind = .mandatory(message: mandMsg)
            } else if !latVer.isEmpty, current.versionLessThan(latVer) {
                kind = .optional(message: optMsg)
            } else {
                kind = .none
            }
        } catch {
            // Fail silently — no banner if Firestore is unreachable at launch.
        }
    }

    func openAppStore() {
        UIApplication.shared.open(Self.storeURL)
    }
}

// MARK: - Blocking screen for mandatory updates

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

// MARK: - Helpers

private extension Bundle {
    var shortVersionString: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}

private extension String {
    /// Returns true when self is semantically lower than other (e.g. "1.2.0" < "1.3.0").
    func versionLessThan(_ other: String) -> Bool {
        compare(other, options: .numeric) == .orderedAscending
    }
}
