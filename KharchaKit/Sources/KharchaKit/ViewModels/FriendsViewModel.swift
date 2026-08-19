import Foundation
import Observation

@MainActor
public final class FriendsViewModel: ObservableObject {
    public struct Row: Sendable, Equatable {
        public let id: UUID
        public let name: String
        public let net: Decimal

        public init(id: UUID, name: String, net: Decimal) {
            self.id = id
            self.name = name
            self.net = net
        }
    }

    public struct State: Sendable {
        public var rows: [Row] = []
        public var errorMessage: String?
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore

    public init(store: ExpenseStore) {
        self.store = store
    }

    public func load() async {
        do {
            let friends = try await store.friends()
            let balances = try await store.netBalances()

            let rows = friends.map { friend in
                Row(id: friend.id, name: friend.name, net: balances[friend.id] ?? 0)
            }

            // Sort: positive nets desc (most-owed first), then zero, then negative (most-owed-to first)
            let sorted = rows.sorted { lhs, rhs in
                let lhsRank = lhs.net > 0 ? 0 : (lhs.net == 0 ? 1 : 2)
                let rhsRank = rhs.net > 0 ? 0 : (rhs.net == 0 ? 1 : 2)

                if lhsRank != rhsRank { return lhsRank < rhsRank }

                // Within same rank
                if lhsRank == 0 { return lhs.net > rhs.net }  // positive: desc
                if lhsRank == 1 { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }  // zero: name asc
                return abs(lhs.net) > abs(rhs.net)  // negative: abs desc
            }

            state.rows = sorted
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func addFriend(name: String) async {
        state.errorMessage = nil

        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            state.errorMessage = "Enter a friend's name."
            return
        }

        do {
            _ = try await store.addFriend(name: trimmed, phone: nil)
            await load()
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func deleteFriend(_ id: UUID) async {
        do {
            try await store.deleteFriend(friendID: id)
            await load()
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}
