import SwiftUI
import KharchaKit

/// Signed-in user's profile: identity header (avatar/name/email), backup & sync
/// controls, and sign-out. Reached from Settings → Account when signed in.
struct ProfileView: View {
    let store: ExpenseStore
    @EnvironmentObject private var signIn: SignInManager
    @State private var isSyncing = false
    @State private var statusMessage: String?
    @State private var showRestoreConfirm = false

    private var initials: String {
        let source = signIn.displayName ?? "K"
        let letters = source.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "K" : String(letters).uppercased()
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Color.brandGradient).frame(width: 64, height: 64)
                        Text(initials)
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(signIn.displayName ?? "Signed in with Apple")
                            .font(.headline)
                        if let email = signIn.email {
                            Text(email).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section {
                Button {
                    Task { await backUp() }
                } label: {
                    if isSyncing {
                        HStack { ProgressView(); Text("Working…") }
                    } else {
                        Label("Back Up Now", systemImage: "arrow.up.doc")
                    }
                }
                .disabled(isSyncing || signIn.firebaseUID == nil)

                Button {
                    showRestoreConfirm = true
                } label: {
                    Label("Restore from Backup", systemImage: "arrow.down.doc")
                }
                .disabled(isSyncing || signIn.firebaseUID == nil)
            } header: {
                Text("Backup & Sync")
            } footer: {
                Text(statusMessage ?? "Your expenses sync automatically across your devices.")
            }

            Section {
                Button("Sign Out", role: .destructive) { signIn.signOut() }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Restore from Backup?", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("Restore", role: .destructive) { Task { await restore() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pulls your cloud data onto this device, overwriting matching local records.")
        }
    }

    private func backUp() async {
        guard let uid = signIn.firebaseUID else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await FirestoreSync(uid: uid, store: store).pushAll()
            statusMessage = "Backed up just now."
        } catch {
            statusMessage = "Backup failed."
        }
    }

    private func restore() async {
        guard let uid = signIn.firebaseUID else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await FirestoreSync(uid: uid, store: store).pullAll()
            statusMessage = "Restored from backup."
            NotificationCenter.default.post(name: .kharchaRemoteDidChange, object: nil)
        } catch {
            statusMessage = "Restore failed."
        }
    }
}
