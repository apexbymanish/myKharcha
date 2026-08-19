import Foundation

public enum LogDebtHandler {
    public static func run(store: ExpenseStore, friendID: UUID, friendName: String, amount: Decimal, direction: DebtDirection, note: String?, now: Date) async throws -> LogResult {
        let debt = try await store.addDebt(friendID: friendID, amount: amount, direction: direction, date: now, note: note, dueDate: nil)
        let net = try await store.netBalance(friendID: friendID)
        let message: String
        switch direction {
        case .iGave:
            message = "Noted — \(friendName) owes you \(AmountFormatter.krw(amount)) (total \(AmountFormatter.krw(net)))."
        case .iTook:
            message = "Noted — you owe \(friendName) \(AmountFormatter.krw(amount)) (total \(AmountFormatter.krw(abs(net))))."
        }
        return LogResult(txnID: debt.id, needsDuplicateConfirmation: false, message: message)
    }
}

public struct SettleResult: Sendable, Equatable {
    public let settledAmount: Decimal
    public let remainingOwed: Decimal
    public let message: String
    public init(settledAmount: Decimal, remainingOwed: Decimal, message: String) {
        self.settledAmount = settledAmount
        self.remainingOwed = remainingOwed
        self.message = message
    }
}

public enum SettleDebtHandler {
    public static func run(store: ExpenseStore, friendID: UUID, friendName: String, amount: Decimal?, now: Date) async throws -> SettleResult {
        let open = try await store.openDebts().filter { $0.friendID == friendID && $0.direction == .iGave }
        guard !open.isEmpty else { throw StoreError.notFound }
        let totalRemaining = open.reduce(Decimal(0)) { $0 + $1.remaining }
        let toSettle = amount ?? totalRemaining
        guard toSettle > 0, toSettle <= totalRemaining else { throw StoreError.invalidAmount }

        var left = toSettle
        for debt in open where left > 0 {  // oldest first (openDebts is date-sorted)
            let chunk = min(debt.remaining, left)
            _ = try await store.settleDebt(debtID: debt.id, amount: chunk)
            left -= chunk
        }
        let remaining = totalRemaining - toSettle
        let message = remaining == 0
            ? "\(friendName) is all settled up."
            : "Settled \(AmountFormatter.krw(toSettle)) — \(friendName) still owes you \(AmountFormatter.krw(remaining))."
        return SettleResult(settledAmount: toSettle, remainingOwed: remaining, message: message)
    }
}

public struct DebtOverview: Sendable, Equatable {
    public let theyOweMe: [CategorySpend]
    public let iOwe: [CategorySpend]
    public let message: String
    public init(theyOweMe: [CategorySpend], iOwe: [CategorySpend], message: String) {
        self.theyOweMe = theyOweMe
        self.iOwe = iOwe
        self.message = message
    }
}

public enum DebtQueryHandler {
    public static func run(store: ExpenseStore) async throws -> DebtOverview {
        var theyOweMe: [CategorySpend] = []
        var iOwe: [CategorySpend] = []
        for friend in try await store.friends() {
            let net = try await store.netBalance(friendID: friend.id)
            if net > 0 { theyOweMe.append(CategorySpend(categoryID: nil, categoryName: friend.name, amount: net)) }
            if net < 0 { iOwe.append(CategorySpend(categoryID: nil, categoryName: friend.name, amount: abs(net))) }
        }
        theyOweMe.sort { $0.amount > $1.amount }
        iOwe.sort { $0.amount > $1.amount }
        let owedToMe = theyOweMe.reduce(Decimal(0)) { $0 + $1.amount }
        let owedByMe = iOwe.reduce(Decimal(0)) { $0 + $1.amount }
        let message: String
        switch (owedToMe > 0, owedByMe > 0) {
        case (false, false): message = "No open debts."
        case (true, false):
            let who = theyOweMe.count == 1 ? "1 friend owes" : "\(theyOweMe.count) friends owe"
            message = "\(who) you \(AmountFormatter.krw(owedToMe)) in total."
        case (false, true): message = "You owe \(AmountFormatter.krw(owedByMe)) in total."
        case (true, true): message = "Friends owe you \(AmountFormatter.krw(owedToMe)); you owe \(AmountFormatter.krw(owedByMe))."
        }
        return DebtOverview(theyOweMe: theyOweMe, iOwe: iOwe, message: message)
    }
}
