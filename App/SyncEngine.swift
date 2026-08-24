import Foundation
import FirebaseFirestore
import KharchaKit

extension Notification.Name {
    /// Posted after remote changes have been applied to the local store, so
    /// visible screens can refresh.
    static let kharchaRemoteDidChange = Notification.Name("kharchaRemoteDidChange")
}

/// Real-time sync driver. On `start(uid:)` it does an initial restore-or-backup,
/// then attaches Firestore snapshot listeners so remote changes stream in live
/// (a debounced full `pullAll()` — cheap at personal scale, and idempotent
/// thanks to the newest-wins/​tombstone-aware upserts). Outbound changes are
/// pushed via `pushNow()` on app lifecycle transitions.
@MainActor
final class SyncEngine: ObservableObject {
    private let store: ExpenseStore
    private var listeners: [ListenerRegistration] = []
    private var uid: String?
    private var pullTask: Task<Void, Never>?

    init(store: ExpenseStore) { self.store = store }

    func start(uid: String) {
        guard uid != self.uid else { return }
        stop()
        self.uid = uid
        let store = store
        Task {
            let sync = FirestoreSync(uid: uid, store: store)
            do {
                if try await store.isEmptyForSync() {
                    try await sync.pullAll()
                    NotificationCenter.default.post(name: .kharchaRemoteDidChange, object: nil)
                } else {
                    try await sync.pushAll()
                }
            } catch { /* offline / transient — listeners will catch up */ }
            self.attachListeners(uid: uid)
        }
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
        pullTask?.cancel()
        pullTask = nil
        uid = nil
    }

    /// Push local → cloud (call on background / resign-active).
    func pushNow() {
        guard let uid else { return }
        let store = store
        Task { try? await FirestoreSync(uid: uid, store: store).pushAll() }
    }

    private func attachListeners(uid: String) {
        let base = Firestore.firestore().collection("users").document(uid)
        for name in ["categories", "friends", "txns", "debts", "rules", "savingsPots", "savingsEntries", "savingsGoals", "installments", "installmentPayments", "tombstones"] {
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
            try? await FirestoreSync(uid: uid, store: store).pullAll()
            NotificationCenter.default.post(name: .kharchaRemoteDidChange, object: nil)
        }
    }
}
