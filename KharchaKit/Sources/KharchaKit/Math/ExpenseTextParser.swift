import Foundation

/// One candidate expense extracted from pasted text, before the user reviews it.
public struct ParsedExpense: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var amount: Decimal
    public var date: Date
    public var note: String
    /// A free-text category name suggested by the parser/model; the view model
    /// maps it to a real category id (or nil = Uncategorized) at review time.
    public var categoryName: String?
    /// Whether this looks like money received (income/gain) rather than spent.
    public var kind: TxnKind
    /// ISO 4217 currency detected for this amount (e.g. "USD"); nil = the app's
    /// base currency. The import step converts non-base amounts before storing.
    public var currencyCode: String?

    public init(id: UUID = UUID(), amount: Decimal, date: Date, note: String, categoryName: String? = nil, kind: TxnKind = .expense, currencyCode: String? = nil) {
        self.id = id
        self.amount = amount
        self.date = date
        self.note = note
        self.categoryName = categoryName
        self.kind = kind
        self.currencyCode = currencyCode
    }
}

/// Deterministic, on-device text → expenses parser. No ML — pure regex +
/// `NSDataDetector`. This is the universal fallback (and the primary engine on
/// devices without Apple Intelligence); `ExpenseTextExtractor` layers the
/// Foundation Models LLM on top when available.
public enum ExpenseTextParser {

    /// Parse pasted text line-by-line. A line contributes one expense when it
    /// contains a parseable amount; any detected date is used (else `now`), and
    /// the leftover text becomes the note.
    public static func parse(_ text: String, now: Date, calendar: Calendar = .current) -> [ParsedExpense] {
        let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        var results: [ParsedExpense] = []

        text.enumerateLines { rawLine, _ in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return }

            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)

            // Detect a date and remember its span so we don't mistake the year
            // (or day number) for the amount.
            var date = now
            var dateRange: NSRange?
            if let match = dateDetector?.firstMatch(in: line, range: full), let d = match.date {
                date = d
                dateRange = match.range
            }

            guard let (amount, amountRange) = firstAmount(in: ns, full: full, excluding: dateRange) else { return }

            // Note = the line with the amount and date spans removed. Delete the
            // later span first so the earlier NSRange stays valid.
            let mutable = NSMutableString(string: ns)
            for range in [amountRange, dateRange].compactMap({ $0 }).sorted(by: { $0.location > $1.location }) {
                mutable.replaceCharacters(in: range, with: " ")
            }
            let note = (mutable as String)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t-–—:•,.|₹$€£¥₩"))
                .replacingOccurrences(of: "  ", with: " ")

            let kind: TxnKind = isIncomeText(line) ? .income : .expense
            let currency = CurrencyDetector.code(in: line)
            results.append(ParsedExpense(amount: amount, date: date, note: note, kind: kind, currencyCode: currency))
        }
        return results
    }

    /// Heuristic: does this text describe money coming IN (income/gain) rather
    /// than being spent? Single-word cues match on word boundaries so "gain"
    /// doesn't fire on "bargain" and "credited" doesn't fire on "credit card".
    public static func isIncomeText(_ text: String) -> Bool {
        let lower = text.lowercased()
        if incomePhrases.contains(where: { lower.contains($0) }) { return true }
        let words = Set(lower.split { !$0.isLetter }.map(String.init))
        return !words.isDisjoint(with: incomeWords)
    }

    private static let incomeWords: Set<String> = [
        "salary", "income", "received", "refund", "refunded", "cashback",
        "credited", "deposit", "deposited", "earned", "bonus", "gain", "gained",
        "paycheck", "payday", "reimbursed", "reimbursement", "dividend", "payout"
    ]
    private static let incomePhrases = ["got paid", "paid me"]

    /// A stable key for de-duplication: amount + calendar day + normalized note.
    /// Used both within a paste and against existing stored transactions.
    public static func dedupKey(amount: Decimal, date: Date, note: String, calendar: Calendar = .current) -> String {
        let day = Int(calendar.startOfDay(for: date).timeIntervalSince1970)
        let amt = NSDecimalNumber(decimal: amount).stringValue
        let n = note.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(amt)|\(day)|\(n)"
    }

    /// Parse a written amount ("₹1,200", "5000", "12.50") into a positive Decimal.
    public static func decimal(from token: String) -> Decimal? {
        let cleaned = token
            .filter { $0.isNumber || $0 == "." || $0 == "," }
            .replacingOccurrences(of: ",", with: "")
        guard let value = Decimal(string: cleaned), value > 0 else { return nil }
        return value
    }

    /// Best-effort date out of a free-text fragment ("yesterday", "Jan 5 2026").
    public static func date(from text: String, now: Date) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let ns = trimmed as NSString
        return detector?.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length))?.date
    }

    // MARK: - Internals

    private static let amountRegex = try? NSRegularExpression(pattern: #"[₹$€£¥₩]?\s?\d[\d,]*(?:\.\d+)?"#)

    /// First numeric token in the line that parses to a positive amount and
    /// doesn't fall inside the detected date span.
    private static func firstAmount(in ns: NSString, full: NSRange, excluding dateRange: NSRange?) -> (Decimal, NSRange)? {
        guard let amountRegex else { return nil }
        for match in amountRegex.matches(in: ns as String, range: full) {
            if let dateRange, NSIntersectionRange(match.range, dateRange).length > 0 { continue }
            let token = ns.substring(with: match.range)
            if let amount = decimal(from: token) {
                return (amount, match.range)
            }
        }
        return nil
    }
}
