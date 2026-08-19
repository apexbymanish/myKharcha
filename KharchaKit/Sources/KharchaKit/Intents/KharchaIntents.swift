import AppIntents
import Foundation
import SwiftUI

public struct LogExpenseIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log Expense"
    public static let description = IntentDescription("Logs an expense in Kharcha.")
    // spec §8: logging allowed from a locked device
    public static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Amount") public var amount: Double
    @Parameter(title: "Category") public var category: CategoryEntity?
    @Parameter(title: "Note") public var note: String?

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = try IntentStoreProvider.store()
        let money = Decimal(siriDouble: amount)
        var result = try await LogExpenseHandler.run(
            store: store, amount: money,
            categoryID: category?.id, categoryName: category?.name,
            note: note, now: Date(), confirmedDuplicate: false
        )
        if result.needsDuplicateConfirmation {
            try await requestConfirmation(dialog: IntentDialog(stringLiteral: result.message))
            result = try await LogExpenseHandler.run(
                store: store, amount: money,
                categoryID: category?.id, categoryName: category?.name,
                note: note, now: Date(), confirmedDuplicate: true
            )
        }
        return .result(dialog: IntentDialog(stringLiteral: result.message)) {
            LogConfirmationCard(message: result.message)
        }
    }
}

public struct LogIncomeIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log Income"
    public static let description = IntentDescription("Logs income in Kharcha.")
    // spec §8: logging allowed from a locked device
    public static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Amount") public var amount: Double
    @Parameter(title: "Note") public var note: String?

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = try IntentStoreProvider.store()
        let money = Decimal(siriDouble: amount)
        let result = try await LogIncomeHandler.run(store: store, amount: money, note: note, now: Date())
        return .result(dialog: IntentDialog(stringLiteral: result.message)) {
            LogConfirmationCard(message: result.message)
        }
    }
}

public struct SpendingQueryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Spending Summary"
    public static let description = IntentDescription("Tells you how much you've spent.")
    // default .requiresAuthentication is the spec-required behavior (queries need unlock) — do not relax

    @Parameter(title: "Period", default: .today) public var period: PeriodAppEnum
    @Parameter(title: "Category") public var category: CategoryEntity?

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = try IntentStoreProvider.store()
        let summary = try await SpendingQueryHandler.run(
            store: store, period: period.period,
            categoryID: category?.id, categoryName: category?.name,
            now: Date(), calendar: Calendar.current
        )
        return .result(dialog: IntentDialog(stringLiteral: summary.message)) {
            SpendingCard(summary: summary)
        }
    }
}

public struct BudgetStatusIntent: AppIntent {
    public static let title: LocalizedStringResource = "Budget Status"
    public static let description = IntentDescription("Tells you how your budgets are tracking.")
    // default .requiresAuthentication is the spec-required behavior (queries need unlock) — do not relax

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = try IntentStoreProvider.store()
        let report = try await BudgetStatusHandler.run(store: store, now: Date(), calendar: Calendar.current)
        return .result(dialog: IntentDialog(stringLiteral: report.message)) {
            BudgetCard(report: report)
        }
    }
}

public struct AddReminderIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add Reminder"
    public static let description = IntentDescription("Adds a recurring reminder in Kharcha.")
    // spec §8: logging allowed from a locked device
    public static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Name") public var name: String
    @Parameter(title: "Amount") public var amount: Double
    @Parameter(title: "Day of Month") public var dayOfMonth: Int
    @Parameter(title: "Remind Days Before", default: 1) public var remindDaysBefore: Int

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = try IntentStoreProvider.store()
        let money = Decimal(siriDouble: amount)
        let result = try await AddReminderHandler.run(
            store: store, name: name, amount: money,
            dayOfMonth: dayOfMonth, remindDaysBefore: remindDaysBefore,
            now: Date(), calendar: Calendar.current
        )
        return .result(dialog: IntentDialog(stringLiteral: result.message)) {
            LogConfirmationCard(message: result.message)
        }
    }
}

public enum DebtDirectionAppEnum: String, AppEnum {
    case iGave, iTook
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"
    public static let caseDisplayRepresentations: [DebtDirectionAppEnum: DisplayRepresentation] = [
        .iGave: "I gave", .iTook: "I took"
    ]
    public var direction: DebtDirection { self == .iGave ? .iGave : .iTook }
}

public struct LogDebtIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log Debt"
    public static let description = IntentDescription("Logs money owed between you and a friend.")
    // spec §8: logging allowed from a locked device
    public static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Friend") public var friend: FriendEntity
    @Parameter(title: "Amount") public var amount: Double
    @Parameter(title: "Direction") public var direction: DebtDirectionAppEnum
    @Parameter(title: "Note") public var note: String?

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = try IntentStoreProvider.store()
        let money = Decimal(siriDouble: amount)
        let result = try await LogDebtHandler.run(
            store: store, friendID: friend.id, friendName: friend.name,
            amount: money, direction: direction.direction, note: note, now: Date()
        )
        return .result(dialog: IntentDialog(stringLiteral: result.message)) {
            LogConfirmationCard(message: result.message)
        }
    }
}

public struct SettleDebtIntent: AppIntent {
    public static let title: LocalizedStringResource = "Settle Debt"
    public static let description = IntentDescription("Settles some or all of what a friend owes you.")
    // default .requiresAuthentication is the spec-required behavior (queries need unlock) — do not relax

    @Parameter(title: "Friend") public var friend: FriendEntity
    @Parameter(title: "Amount") public var amount: Double?

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = try IntentStoreProvider.store()
        var money = amount.map { Decimal(siriDouble: $0) }

        // If amount is nil (settle-all), confirm the total owed before proceeding
        if amount == nil {
            let balances = try await store.netBalances()
            if let netOwed = balances[friend.id], netOwed > 0 {
                try await requestConfirmation(
                    dialog: IntentDialog(stringLiteral: "Settle everything \(friend.name) owes you (\(AmountFormatter.krw(netOwed)))?")
                )
            }
        }

        let result = try await SettleDebtHandler.run(
            store: store, friendID: friend.id, friendName: friend.name, amount: money, now: Date()
        )
        return .result(dialog: IntentDialog(stringLiteral: result.message)) {
            LogConfirmationCard(message: result.message)
        }
    }
}

public struct DebtQueryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Debt Overview"
    public static let description = IntentDescription("Tells you who owes whom.")
    // default .requiresAuthentication is the spec-required behavior (queries need unlock) — do not relax

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = try IntentStoreProvider.store()
        let overview = try await DebtQueryHandler.run(store: store)
        return .result(dialog: IntentDialog(stringLiteral: overview.message)) {
            DebtCard(overview: overview)
        }
    }
}
