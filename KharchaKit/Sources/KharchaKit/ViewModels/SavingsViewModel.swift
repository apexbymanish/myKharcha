import Foundation

@MainActor
public final class SavingsViewModel: ObservableObject {
    public struct State: Sendable {
        public var pots: [SavingsPotSnapshot] = []
        public var goals: [SavingsGoalSnapshot] = []
        public var totalBalance: Decimal = 0
        /// The envelope split of `totalBalance` across bills + goals.
        public var allocation: SavingsAllocation?
        public var errorMessage: String?
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore

    public init(store: ExpenseStore) { self.store = store }

    public func load() async {
        state.errorMessage = nil
        do {
            let pots = try await store.savingsPots()
            let goals = try await store.savingsGoals()
            let rules = try await store.recurringRules()
            let total = pots.reduce(Decimal(0)) { $0 + $1.balance }

            // Bills first (reserved by day-of-month), then goals.
            var obligations = rules.map {
                SavingsObligation(name: $0.name, amount: $0.amount, priority: $0.dayOfMonth)
            }
            obligations += goals.map {
                SavingsObligation(name: $0.name, amount: $0.targetAmount, priority: 1000 + $0.priority)
            }

            state.pots = pots
            state.goals = goals
            state.totalBalance = total
            state.allocation = SavingsAllocator.plan(balance: total, obligations: obligations)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func addPot(name: String, note: String?) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { state.errorMessage = "Enter a bank/pot name."; return }
        await run { _ = try await self.store.addSavingsPot(name: trimmed, note: note?.isEmpty == true ? nil : note) }
    }

    /// `amount` is signed: positive = deposit, negative = withdrawal.
    public func addEntry(potID: UUID, amount: Decimal, note: String, date: Date = Date()) async {
        guard amount != 0 else { state.errorMessage = "Enter a non-zero amount."; return }
        await run { _ = try await self.store.addSavingsEntry(potID: potID, amount: amount, note: note.isEmpty ? nil : note, date: date) }
    }

    public func addGoal(name: String, targetAmount: Decimal, priority: Int) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { state.errorMessage = "Enter a goal name."; return }
        guard targetAmount > 0 else { state.errorMessage = "Enter a valid target."; return }
        await run { _ = try await self.store.addSavingsGoal(name: trimmed, targetAmount: targetAmount, priority: priority) }
    }

    public func entries(potID: UUID) async -> [SavingsEntrySnapshot] {
        (try? await store.savingsEntries(potID: potID)) ?? []
    }

    public func deletePot(id: UUID) async { await run { try await self.store.deleteSavingsPot(id: id) } }
    public func deleteEntry(id: UUID) async { await run { try await self.store.deleteSavingsEntry(id: id) } }
    public func deleteGoal(id: UUID) async { await run { try await self.store.deleteSavingsGoal(id: id) } }

    private func run(_ op: () async throws -> Void) async {
        state.errorMessage = nil
        do { try await op(); await load() }
        catch { state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong." }
    }
}
