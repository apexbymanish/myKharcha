import SwiftData

public enum KharchaSchema {
    public static let models: [any PersistentModel.Type] = [
        Txn.self, Category.self, RecurringRule.self, Friend.self, Debt.self, Tombstone.self,
        SavingsPot.self, SavingsEntry.self, SavingsGoal.self,
        Installment.self, InstallmentPayment.self
    ]
}
