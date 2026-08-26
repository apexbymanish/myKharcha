import Foundation

@MainActor
public final class ImportViewModel: ObservableObject {
    public struct Row: Identifiable, Sendable, Equatable {
        public let id: UUID
        public var amount: Decimal
        public var date: Date
        public var note: String
        public var categoryID: UUID?
        public var include: Bool
        /// Income vs expense, as detected by the model/parser (user can't flip it
        /// here — re-paste or edit after import if the detection is wrong).
        public var kind: TxnKind
        /// When the pasted amount was in a foreign currency, the original amount +
        /// code (for display); `amount` above is already converted to base.
        public var originalAmount: Decimal?
        public var originalCurrency: String?
        /// Matches an existing stored transaction or an earlier row in this paste.
        public var isDuplicate: Bool
    }

    public struct State: Sendable {
        public var rows: [Row] = []
        public var categories: [CategorySnapshot] = []
        public var isParsing = false
        /// True when the on-device model produced the results (vs the regex fallback).
        public var usedModel = false
        public var errorMessage: String?
        public var importedCount: Int?
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore
    private let rates: RateProviding?

    public init(store: ExpenseStore, rates: RateProviding? = nil) {
        self.store = store
        self.rates = rates
    }

    /// Parse pasted text into review rows. `allowModel` is false in tests to force
    /// the deterministic parser (the LLM path is non-deterministic / device-gated).
    public func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current, allowModel: Bool = true, baseCurrency: String = AmountFormatter.currencyCode) async {
        state.isParsing = true
        state.errorMessage = nil
        state.importedCount = nil
        defer { state.isParsing = false }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state.rows = []
            return
        }

        do {
            let categories = try await store.categories()
            state.categories = categories

            var parsed: [ParsedExpense] = []
            var usedModel = false
            if allowModel, ExpenseTextExtractor.isAvailable,
               let llm = await ExpenseTextExtractor.extract(text, now: now, calendar: calendar),
               !llm.isEmpty {
                parsed = llm
                usedModel = true
            } else {
                parsed = ExpenseTextParser.parse(text, now: now, calendar: calendar)
            }
            state.usedModel = usedModel

            // Keys of existing transactions, for store-level duplicate flagging.
            let existingKeys = Set(try await store.txnRows().map {
                ExpenseTextParser.dedupKey(amount: $0.amount, date: $0.date, note: $0.note ?? "", calendar: calendar)
            })

            var seen = Set<String>()
            var rows: [Row] = []
            for p in parsed {
                // Convert foreign-currency amounts to the base currency for storage.
                var amount = p.amount
                var originalAmount: Decimal?
                var originalCurrency: String?
                if let code = p.currencyCode, code != baseCurrency, let rates,
                   let rate = await rates.rate(from: code, to: baseCurrency, on: p.date) {
                    amount = CurrencyConverter.convert(p.amount, rate: rate, minorUnits: CurrencyConverter.minorUnits(for: baseCurrency))
                    originalAmount = p.amount
                    originalCurrency = code
                }

                let key = ExpenseTextParser.dedupKey(amount: amount, date: p.date, note: p.note, calendar: calendar)
                let isDuplicate = existingKeys.contains(key) || seen.contains(key)
                seen.insert(key)
                let categoryID = p.categoryName.flatMap { name in
                    categories.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
                }
                // Duplicates default to excluded so a careless Import doesn't double-log.
                rows.append(Row(
                    id: p.id, amount: amount, date: p.date, note: p.note,
                    categoryID: categoryID, include: !isDuplicate, kind: p.kind,
                    originalAmount: originalAmount, originalCurrency: originalCurrency, isDuplicate: isDuplicate
                ))
            }
            state.rows = rows
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    /// Reset the review list and any status messages (Clear button).
    public func clear() {
        state.rows = []
        state.importedCount = nil
        state.errorMessage = nil
    }

    public var selectedCount: Int { state.rows.filter(\.include).count }

    public func setInclude(_ id: UUID, _ value: Bool) {
        guard let i = state.rows.firstIndex(where: { $0.id == id }) else { return }
        state.rows[i].include = value
    }

    public func setCategory(_ id: UUID, _ categoryID: UUID?) {
        guard let i = state.rows.firstIndex(where: { $0.id == id }) else { return }
        state.rows[i].categoryID = categoryID
    }

    public func setNote(_ id: UUID, _ value: String) {
        guard let i = state.rows.firstIndex(where: { $0.id == id }) else { return }
        state.rows[i].note = value
    }

    /// Insert every included row as a manual expense; reports how many landed.
    public func importSelected() async {
        state.errorMessage = nil
        do {
            var count = 0
            for row in state.rows where row.include {
                _ = try await store.addTxn(
                    amount: row.amount, kind: row.kind, categoryID: row.categoryID,
                    note: row.note.isEmpty ? nil : row.note, date: row.date, source: .manual
                )
                count += 1
            }
            state.importedCount = count
            state.rows = []
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}
