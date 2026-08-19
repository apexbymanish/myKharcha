import Foundation

public struct LogResult: Sendable, Equatable {
    public let txnID: UUID?
    public let needsDuplicateConfirmation: Bool
    public let message: String
    public init(txnID: UUID?, needsDuplicateConfirmation: Bool, message: String) {
        self.txnID = txnID
        self.needsDuplicateConfirmation = needsDuplicateConfirmation
        self.message = message
    }
}

public enum LogExpenseHandler {
    public static func run(store: ExpenseStore, amount: Decimal, categoryID: UUID?, categoryName: String?, note: String?, now: Date, confirmedDuplicate: Bool) async throws -> LogResult {
        guard amount > 0 else { throw StoreError.invalidAmount }
        if !confirmedDuplicate, try await store.isDuplicate(amount: amount, categoryID: categoryID, now: now) {
            return LogResult(
                txnID: nil,
                needsDuplicateConfirmation: true,
                message: "You just logged \(AmountFormatter.krw(amount)) — log it again?"
            )
        }
        let id = try await store.addTxn(amount: amount, kind: .expense, categoryID: categoryID, note: note, date: now, source: .siri)
        return LogResult(
            txnID: id,
            needsDuplicateConfirmation: false,
            message: "Logged \(AmountFormatter.krw(amount)) for \(categoryName ?? "Uncategorized")."
        )
    }
}

public enum LogIncomeHandler {
    public static func run(store: ExpenseStore, amount: Decimal, note: String?, now: Date) async throws -> LogResult {
        let id = try await store.addTxn(amount: amount, kind: .income, categoryID: nil, note: note, date: now, source: .siri)
        return LogResult(txnID: id, needsDuplicateConfirmation: false, message: "Recorded \(AmountFormatter.krw(amount)) income.")
    }
}
