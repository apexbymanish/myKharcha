import Foundation
import FoundationModels

/// On-device (Apple Intelligence) expense extraction. Handles messy natural
/// language ("spent 500 on lunch, 1.2k taxi yesterday") far better than regex.
///
/// Per Apple's guidance the on-device model is unreliable at arithmetic, so the
/// model only *identifies* the amount and date as they appear in the text; we
/// convert those to `Decimal`/`Date` ourselves (via `ExpenseTextParser`) for
/// exact values. Returns nil when the model is unavailable or errors, so callers
/// fall back to the deterministic parser.
public enum ExpenseTextExtractor {

    @Generable
    struct ExtractedExpense {
        @Guide(description: "The amount exactly as written in the text, e.g. '500', '1,200', or '₹120'. Do not do any math.")
        var amountText: String
        @Guide(description: "The date of this expense if the text mentions one (e.g. 'Jan 5 2026', 'yesterday'); otherwise an empty string.")
        var dateText: String
        @Guide(description: "A short description of what the expense was for.")
        var note: String
        @Guide(description: "A spending category if obvious (Food, Transport, Rent, Shopping, Health, etc.); otherwise an empty string.")
        var category: String
        @Guide(description: "true if this is money received (income, salary, refund, cashback, a gain); false if it is money spent.")
        var isIncome: Bool
        @Guide(description: "The ISO 4217 currency code of the amount if identifiable (e.g. USD, KRW, EUR) — infer from symbols like $, ₩ or words like 'dollars', 'won'. Empty string if unclear.")
        var currencyCode: String
    }

    @Generable
    struct ExtractedExpenseList {
        @Guide(description: "Every distinct expense mentioned in the text. Ignore lines that are not expenses.")
        var expenses: [ExtractedExpense]
    }

    /// Whether the on-device model can run on this device right now.
    public static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    public static func extract(_ text: String, now: Date, calendar: Calendar = .current) async -> [ParsedExpense]? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        do {
            let session = LanguageModelSession()
            let prompt = """
            Extract every money transaction from the text below — both money spent \
            (expenses) and money received (income, salary, refunds, cashback, gains). \
            It may be a note, a chat message, or an email. For each one return the amount \
            exactly as written, an optional date, a short note, an optional category, and \
            whether it is income. Do not perform any arithmetic and do not invent \
            transactions that aren't in the text.

            Text:
            \(text)
            """
            let response = try await session.respond(to: prompt, generating: ExtractedExpenseList.self)
            let parsed = response.content.expenses.compactMap { row -> ParsedExpense? in
                guard let amount = ExpenseTextParser.decimal(from: row.amountText) else { return nil }
                let date = ExpenseTextParser.date(from: row.dateText, now: now) ?? now
                let category = row.category.trimmingCharacters(in: .whitespaces)
                let modelCurrency = row.currencyCode.trimmingCharacters(in: .whitespaces).uppercased()
                let currency = modelCurrency.isEmpty ? CurrencyDetector.code(in: row.amountText) : modelCurrency
                return ParsedExpense(
                    amount: amount,
                    date: date,
                    note: row.note.trimmingCharacters(in: .whitespaces),
                    categoryName: category.isEmpty ? nil : category,
                    kind: row.isIncome ? .income : .expense,
                    currencyCode: currency
                )
            }
            return parsed
        } catch {
            return nil
        }
    }
}
