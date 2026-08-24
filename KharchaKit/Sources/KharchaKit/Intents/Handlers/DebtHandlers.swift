import Foundation

public enum LogDebtHandler {
    public static func run(store: ExpenseStore, friendID: UUID, friendName: String, amount: Decimal, direction: DebtDirection, note: String?, now: Date) async throws -> LogResult {
        let debt = try await store.addDebt(friendID: friendID, amount: amount, direction: direction, date: now, note: note, dueDate: nil)
        let net = try await store.netBalance(friendID: friendID)
        let message: String
        switch direction {
        case .iGave where net >= 0:
            message = "Noted — \(friendName) owes you \(AmountFormatter.money(amount)) (total \(AmountFormatter.money(net)))."
        case .iTook where net <= 0:
            message = "Noted — you owe \(friendName) \(AmountFormatter.money(amount)) (total \(AmountFormatter.money(abs(net))))."
        case .iGave:
            message = "Noted — \(friendName) owes you \(AmountFormatter.money(amount)) (overall you still owe \(AmountFormatter.money(abs(net))))."
        case .iTook:
            message = "Noted — you owe \(friendName) \(AmountFormatter.money(amount)) (overall \(friendName) still owes you \(AmountFormatter.money(net)))."
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
        let (toSettle, remaining) = try await store.settleFriendDebts(friendID: friendID, amount: amount)
        let message = remaining == 0
            ? "\(friendName) is all settled up."
            : "Settled \(AmountFormatter.money(toSettle)) — \(friendName) still owes you \(AmountFormatter.money(remaining))."
        return SettleResult(settledAmount: toSettle, remainingOwed: remaining, message: message)
    }
}

public struct DebtRow: Sendable, Equatable {
    public let friendID: UUID
    public let name: String
    public let amount: Decimal
    public init(friendID: UUID, name: String, amount: Decimal) {
        self.friendID = friendID
        self.name = name
        self.amount = amount
    }
}

public struct DebtOverview: Sendable, Equatable {
    public let theyOweMe: [DebtRow]
    public let iOwe: [DebtRow]
    public let message: String
    public init(theyOweMe: [DebtRow], iOwe: [DebtRow], message: String) {
        self.theyOweMe = theyOweMe
        self.iOwe = iOwe
        self.message = message
    }
}

public enum DebtQueryHandler {
    private static func sorted(_ rows: [DebtRow]) -> [DebtRow] {
        rows.sorted {
            $0.amount != $1.amount
                ? $0.amount > $1.amount
                : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public static func run(store: ExpenseStore) async throws -> DebtOverview {
        let balances = try await store.netBalances()
        var theyOweMe: [DebtRow] = []
        var iOwe: [DebtRow] = []
        for friend in try await store.friends() {
            let net = balances[friend.id] ?? 0
            if net > 0 { theyOweMe.append(DebtRow(friendID: friend.id, name: friend.name, amount: net)) }
            if net < 0 { iOwe.append(DebtRow(friendID: friend.id, name: friend.name, amount: abs(net))) }
        }
        theyOweMe = sorted(theyOweMe)
        iOwe = sorted(iOwe)
        let owedToMe = theyOweMe.reduce(Decimal(0)) { $0 + $1.amount }
        let owedByMe = iOwe.reduce(Decimal(0)) { $0 + $1.amount }
        let message: String
        switch (owedToMe > 0, owedByMe > 0) {
        case (false, false): message = "No open debts."
        case (true, false):
            let who = theyOweMe.count == 1 ? "1 friend owes" : "\(theyOweMe.count) friends owe"
            message = "\(who) you \(AmountFormatter.money(owedToMe)) in total."
        case (false, true): message = "You owe \(AmountFormatter.money(owedByMe)) in total."
        case (true, true):
            let who = theyOweMe.count == 1 ? "1 friend owes" : "\(theyOweMe.count) friends owe"
            message = "\(who) you \(AmountFormatter.money(owedToMe)); you owe \(AmountFormatter.money(owedByMe))."
        }
        return DebtOverview(theyOweMe: theyOweMe, iOwe: iOwe, message: message)
    }
}
