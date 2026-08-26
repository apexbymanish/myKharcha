import Foundation
import FirebaseFirestore
import KharchaKit

extension Notification.Name {
    /// Posted after remote changes have been applied to the local store, so
    /// visible screens can refresh.
    static let kharchaRemoteDidChange = Notification.Name("kharchaRemoteDidChange")
}

/// Real-time sync driver.
///
/// On `start(uid:)` it always pulls from Firestore first (restoring any cloud
/// data, including from other devices), then pushes local data on top. This
/// handles all cases safely via newest-wins `updatedAt` conflict resolution:
/// - New device, empty local → pull restores, push is a no-op.
/// - Existing device → pull merges remote changes, push backs up local.
/// - Data added locally before sign-in → pull merges cloud, push backs up all.
/// - Offline at sign-in → sets `needsInitialPull`; retried on next foreground.
///
/// After the initial sync, Firestore snapshot listeners stream in changes live.
/// Outbound changes are pushed via `pushNow()` on app lifecycle transitions.
@MainActor
final class SyncEngine: ObservableObject {
    private let store: ExpenseStore
    private var listeners: [ListenerRegistration] = []
    private var uid: String?
    private var pullTask: Task<Void, Never>?
    private var needsInitialPull = false

    @Published private(set) var isSyncing = false
    @Published private(set) var hasSyncError = false
    /// Persisted across launches so ProfileView can show "Last synced X ago" immediately.
    @Published private(set) var lastSyncedAt: Date? =
        UserDefaults.standard.object(forKey: "sync.lastSyncedAt") as? Date

    init(store: ExpenseStore) { self.store = store }

    func start(uid: String) {
        guard uid != self.uid else { return }
        stop()
        self.uid = uid
        isSyncing = true
        hasSyncError = false
        needsInitialPull = false
        let store = store
        Task {
            let sync = FirestoreSync(uid: uid, store: store)
            do {
                // Pull first so remote-only data isn't lost, then push so local
                // data (including anything added before sign-in) is backed up.
                try await sync.pullAll()
                NotificationCenter.default.post(name: .kharchaRemoteDidChange, object: nil)
                try await sync.pushAll()
                markSyncSuccess()
            } catch {
                hasSyncError = true
                needsInitialPull = true   // retry next foreground
            }
            isSyncing = false
            self.attachListeners(uid: uid)
        }
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
        pullTask?.cancel()
        pullTask = nil
        uid = nil
        needsInitialPull = false
        isSyncing = false
    }

    /// Retries the initial pull+push if it previously failed (e.g. offline).
    /// Call on every app foreground while signed in.
    func retryInitialPullIfNeeded() {
        guard needsInitialPull, let uid else { return }
        needsInitialPull = false
        isSyncing = true
        hasSyncError = false
        let store = store
        Task {
            let sync = FirestoreSync(uid: uid, store: store)
            do {
                try await sync.pullAll()
                NotificationCenter.default.post(name: .kharchaRemoteDidChange, object: nil)
                try await sync.pushAll()
                markSyncSuccess()
            } catch {
                hasSyncError = true
                needsInitialPull = true
            }
            isSyncing = false
        }
    }

    /// Push local → cloud (call on background / resign-active).
    func pushNow() {
        guard let uid else { return }
        let store = store
        Task {
            do {
                try await FirestoreSync(uid: uid, store: store).pushAll()
                markSyncSuccess()
            } catch {
                hasSyncError = true
            }
        }
    }

    private func markSyncSuccess() {
        let now = Date()
        lastSyncedAt = now
        hasSyncError = false
        UserDefaults.standard.set(now, forKey: "sync.lastSyncedAt")
    }

    private func attachListeners(uid: String) {
        let base = Firestore.firestore().collection("users").document(uid)
        for name in ["categories", "friends", "txns", "debts", "rules", "savingsPots",
                     "savingsEntries", "savingsGoals", "installments", "installmentPayments", "tombstones"] {
            let listener = base.collection(name).addSnapshotListener { [weak self] snapshot, _ in
                // Skip echoes of our own not-yet-committed writes.
                guard let snapshot, !snapshot.metadata.hasPendingWrites else { return }
                Task { @MainActor in self?.schedulePull() }
            }
            listeners.append(listener)
        }
    }

    /// Debounce bursts of listener callbacks into a single full pull.
    private func schedulePull() {
        guard let uid else { return }
        let store = store
        pullTask?.cancel()
        pullTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            do {
                try await FirestoreSync(uid: uid, store: store).pullAll()
                NotificationCenter.default.post(name: .kharchaRemoteDidChange, object: nil)
                markSyncSuccess()
            } catch {
                hasSyncError = true
            }
        }
    }
}
