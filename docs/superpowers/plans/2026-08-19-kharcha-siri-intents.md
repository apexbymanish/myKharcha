# Kharcha Siri Intents Implementation Plan (Plan 2 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Siri App Intents layer to `KharchaKit` — 8 intents, entities/enums, testable intent handlers, and snippet card views — plus the store extensions the intents need, fully test-driven under `swift test`.

**Architecture:** Every intent is a thin `AppIntent` wrapper over a pure, testable **handler** (`Intents/Handlers/`): handlers take an `ExpenseStore` + plain values and return plain result structs — no AppIntents types — so all business behavior is unit-tested without the Siri runtime. Entities (`CategoryEntity`, `FriendEntity`) and the `PeriodAppEnum` resolve through the same store. A cached `IntentStoreProvider` gives intents the shared App Group container in production and an in-memory container in tests. Snippet views are plain SwiftUI, compile-verified.

**Tech Stack:** Swift 6.2+, AppIntents, SwiftData, SwiftUI, Swift Testing. Zero third-party deps.

**Spec:** `docs/superpowers/specs/2026-08-14-kharcha-app-design.md` (§5 intents catalog, §8 error handling)

## Global Constraints

- Platforms already set (`.iOS(.v26)`, `.macOS(.v26)`); all AppIntents/SwiftUI code must compile for BOTH platforms (guard iOS-only API with `#if os(iOS)` only if truly unavoidable).
- Money is always `Decimal`. Siri delivers `Double` parameters — convert ONLY via the `Decimal(siriDouble:)` helper (Task 3), never `Decimal(double)` directly.
- Handlers never import AppIntents. Intent wrappers contain no business logic beyond parameter conversion and dialog assembly.
- All store access via `ExpenseStore`; fetch broadly + filter in memory (never `#Predicate`); public API stays UUIDs + Sendable snapshots.
- Time-sensitive APIs take `now: Date`/`calendar: Calendar`; intent wrappers pass `Date()`/`Calendar.current`, handlers/tests pass fixed values.
- Dialog/message strings are English literals for now (localization is a later plan).
- Tests use `import Testing`; test helpers `testCal`/`d(...)`/`makeStore()` exist in `KharchaKit/Tests/KharchaKitTests/TestSupport.swift`.
- AppShortcutsProvider (phrases) is NOT in this plan — Apple requires it in the app bundle, so it ships with Plan 3.
- Commit after every task with the given message.

**Working directory for all commands:** `~/Developer/Kharcha` (package at `KharchaKit/`; suite baseline 50/50 green at branch point `d6d877c`).

---

### Task 1: Parked fix — `ensureOtherCategory` backfills `isFallback`

**Files:**
- Modify: `KharchaKit/Sources/KharchaKit/Store/ExpenseStore.swift` (the `ensureOtherCategory()` private helper)
- Test: `KharchaKit/Tests/KharchaKitTests/DeleteRulesTests.swift` (append)

**Interfaces:**
- Consumes: existing `ensureOtherCategory()` name-based safety net.
- Produces: no API change — the adopted legacy "Other" category gets `isFallback = true` persisted, so the delete guard protects it.

- [ ] **Step 1: Write the failing test** (append to DeleteRulesTests.swift)

```swift
@Test func legacyOtherCategoryIsAdoptedAsFallback() async throws {
    let store = try makeStore()
    // Simulate a pre-isFallback store: an "Other" created WITHOUT the flag.
    let legacyOther = try await store.addCategory(name: "Other", symbol: "tag", colorHex: "#9A9A9A", monthlyBudget: nil)
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)

    // deleteCategory triggers ensureOtherCategory, which must adopt AND flag the legacy category.
    try await store.deleteCategory(categoryID: food.id)

    let categories = try await store.categories()
    #expect(categories.first { $0.id == legacyOther.id }?.isFallback == true)
    await #expect(throws: StoreError.cannotDeleteFallbackCategory) {
        try await store.deleteCategory(categoryID: legacyOther.id)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test --filter legacyOtherCategoryIsAdoptedAsFallback`
Expected: FAIL — `isFallback` stays false, second `deleteCategory` does not throw

- [ ] **Step 3: Fix** — in `ensureOtherCategory()`, the name-based branch must backfill before returning:

```swift
        // Safety net: an older store might have an "Other" category that predates the isFallback flag.
        if let other = try modelContext.fetch(FetchDescriptor<Category>()).first(where: { $0.name == "Other" }) {
            other.isFallback = true
            other.updatedAt = .now
            return other
        }
```

(Match the actual surrounding code — the isFallback-based lookup above it stays first.)

- [ ] **Step 4: Run the full suite** — `swift test` — expect all green (51 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/Kharcha && git add KharchaKit && git commit -m "fix: backfill isFallback when adopting a legacy Other category"
```

---

### Task 2: Store additions — recurring-rule CRUD + spending breakdown

**Files:**
- Modify: `KharchaKit/Sources/KharchaKit/Store/ExpenseStore.swift`
- Create: `KharchaKit/Sources/KharchaKit/Store/RecurringRuleSnapshot.swift`
- Create: `KharchaKit/Sources/KharchaKit/Math/SpendingBreakdown.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/RecurringRuleStoreTests.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/SpendingBreakdownTests.swift`

**Interfaces:**
- Produces (intents consume these):
  - `struct RecurringRuleSnapshot: Sendable, Equatable { public let id: UUID; public let name: String; public let amount: Decimal; public let categoryName: String; public let dayOfMonth: Int; public let remindDaysBefore: Int; public let autoLog: Bool; public init(...) }` (public memberwise init — the package's public-surface rule)
  - `ExpenseStore.addRecurringRule(name: String, amount: Decimal, categoryID: UUID?, dayOfMonth: Int, remindDaysBefore: Int, autoLog: Bool) throws -> RecurringRuleSnapshot` — throws `.invalidAmount` for amount ≤ 0 or dayOfMonth outside 1...31; `.notFound` for non-nil unknown categoryID
  - `ExpenseStore.recurringRules() throws -> [RecurringRuleSnapshot]` sorted by dayOfMonth then name
  - `ExpenseStore.deleteRecurringRule(ruleID: UUID) throws` — `.notFound` for unknown ID
  - `struct CategorySpend: Sendable, Equatable { public let categoryID: UUID?; public let categoryName: String; public let amount: Decimal; public init(...) }`
  - `struct SpendingBreakdown: Sendable, Equatable { public let total: Decimal; public let categories: [CategorySpend]; public init(...) }` — categories sorted by amount descending, then name ascending; nil-category txns appear as `categoryName: "Uncategorized"`
  - `ExpenseStore.spendingBreakdown(in period: Period, now: Date, calendar: Calendar) throws -> SpendingBreakdown` — expenses only, single pass over one Txn fetch (same shape as budgetStatuses)

- [ ] **Step 1: Write the failing tests**

`RecurringRuleStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func addAndListRecurringRules() async throws {
    let store = try makeStore()
    try await store.seedDefaultCategoriesIfNeeded()
    let rent = try await store.categories().first { $0.name == "Rent" }!
    let rule = try await store.addRecurringRule(name: "Rent", amount: 500_000, categoryID: rent.id, dayOfMonth: 25, remindDaysBefore: 3, autoLog: false)
    #expect(rule.categoryName == "Rent")
    _ = try await store.addRecurringRule(name: "Netflix", amount: 17_000, categoryID: nil, dayOfMonth: 3, remindDaysBefore: 1, autoLog: true)

    let rules = try await store.recurringRules()
    #expect(rules.map(\.name) == ["Netflix", "Rent"]) // sorted by dayOfMonth
    #expect(rules[0].categoryName == "")
}

@Test func addRecurringRuleValidation() async throws {
    let store = try makeStore()
    await #expect(throws: StoreError.invalidAmount) {
        _ = try await store.addRecurringRule(name: "X", amount: 0, categoryID: nil, dayOfMonth: 5, remindDaysBefore: 1, autoLog: false)
    }
    await #expect(throws: StoreError.invalidAmount) {
        _ = try await store.addRecurringRule(name: "X", amount: 1, categoryID: nil, dayOfMonth: 32, remindDaysBefore: 1, autoLog: false)
    }
    await #expect(throws: StoreError.notFound) {
        _ = try await store.addRecurringRule(name: "X", amount: 1, categoryID: UUID(), dayOfMonth: 5, remindDaysBefore: 1, autoLog: false)
    }
}

@Test func deleteRecurringRule() async throws {
    let store = try makeStore()
    let rule = try await store.addRecurringRule(name: "Gym", amount: 60_000, categoryID: nil, dayOfMonth: 1, remindDaysBefore: 0, autoLog: false)
    try await store.deleteRecurringRule(ruleID: rule.id)
    #expect(try await store.recurringRules().isEmpty)
    await #expect(throws: StoreError.notFound) {
        try await store.deleteRecurringRule(ruleID: rule.id)
    }
}
```

`SpendingBreakdownTests.swift`:

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func breakdownSumsAndRanksCategories() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    let transport = try await store.addCategory(name: "Transport", symbol: "bus", colorHex: "#3D405B", monthlyBudget: nil)

    _ = try await store.addTxn(amount: 30_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 10), source: .manual)
    _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 14), source: .siri)
    _ = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: transport.id, note: nil, date: d(2026, 8, 14), source: .manual)
    _ = try await store.addTxn(amount: 700, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 14), source: .manual)
    _ = try await store.addTxn(amount: 1_000_000, kind: .income, categoryID: nil, note: nil, date: d(2026, 8, 14), source: .manual) // excluded
    _ = try await store.addTxn(amount: 99_999, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 7, 1), source: .manual)  // out of period

    let breakdown = try await store.spendingBreakdown(in: .month, now: d(2026, 8, 15), calendar: testCal)
    #expect(breakdown.total == 47_700)
    #expect(breakdown.categories.map(\.categoryName) == ["Food", "Transport", "Uncategorized"])
    #expect(breakdown.categories[0].amount == 42_000)
}

@Test func emptyStoreBreakdownIsZero() async throws {
    let store = try makeStore()
    let breakdown = try await store.spendingBreakdown(in: .today, now: d(2026, 8, 15), calendar: testCal)
    #expect(breakdown.total == 0)
    #expect(breakdown.categories.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail** (`swift test --filter RecurringRuleStoreTests`; `--filter SpendingBreakdownTests`) — expect "no member" compile failures.

- [ ] **Step 3: Implement.**

`Store/RecurringRuleSnapshot.swift`: the struct as specified in Interfaces (public init covering all fields).

`Math/SpendingBreakdown.swift`: `CategorySpend` + `SpendingBreakdown` as specified (public inits).

Append inside `ExpenseStore` — a new `// MARK: Recurring rules` region:

```swift
    @discardableResult
    public func addRecurringRule(name: String, amount: Decimal, categoryID: UUID?, dayOfMonth: Int, remindDaysBefore: Int, autoLog: Bool) throws -> RecurringRuleSnapshot {
        guard amount > 0, (1...31).contains(dayOfMonth) else { throw StoreError.invalidAmount }
        var category: Category?
        if let categoryID {
            guard let found = try fetchCategory(id: categoryID) else { throw StoreError.notFound }
            category = found
        }
        let rule = RecurringRule(name: name, amount: amount, category: category, dayOfMonth: dayOfMonth, remindDaysBefore: remindDaysBefore, autoLog: autoLog)
        modelContext.insert(rule)
        try modelContext.save()
        return snapshot(rule)
    }

    public func recurringRules() throws -> [RecurringRuleSnapshot] {
        try modelContext.fetch(FetchDescriptor<RecurringRule>())
            .sorted { ($0.dayOfMonth, $0.name) < ($1.dayOfMonth, $1.name) }
            .map(snapshot)
    }

    public func deleteRecurringRule(ruleID: UUID) throws {
        guard let rule = try modelContext.fetch(FetchDescriptor<RecurringRule>()).first(where: { $0.id == ruleID }) else {
            throw StoreError.notFound
        }
        modelContext.delete(rule)
        try modelContext.save()
    }

    private func snapshot(_ rule: RecurringRule) -> RecurringRuleSnapshot {
        RecurringRuleSnapshot(
            id: rule.id, name: rule.name, amount: rule.amount,
            categoryName: rule.category?.name ?? "",
            dayOfMonth: rule.dayOfMonth, remindDaysBefore: rule.remindDaysBefore, autoLog: rule.autoLog
        )
    }
```

And in the Transactions region:

```swift
    /// Single-pass per-category expense breakdown for a period (Siri "how much did I spend").
    public func spendingBreakdown(in period: Period, now: Date, calendar: Calendar) throws -> SpendingBreakdown {
        let range = period.dateRange(now: now, calendar: calendar)
        let expenses = try modelContext.fetch(FetchDescriptor<Txn>())
            .filter { $0.kind == .expense && range.contains($0.date) }
        var buckets: [String: (id: UUID?, amount: Decimal)] = [:]
        var total = Decimal(0)
        for txn in expenses {
            let name = txn.category?.name ?? "Uncategorized"
            var bucket = buckets[name] ?? (txn.category?.id, 0)
            bucket.amount += txn.amount
            buckets[name] = bucket
            total += txn.amount
        }
        let categories = buckets
            .map { CategorySpend(categoryID: $0.value.id, categoryName: $0.key, amount: $0.value.amount) }
            .sorted { ($1.amount, $0.categoryName) < ($0.amount, $1.categoryName) }
        return SpendingBreakdown(total: total, categories: categories)
    }
```

- [ ] **Step 4: Run the full suite** — expect all green.
- [ ] **Step 5: Commit** — `git add KharchaKit && git commit -m "feat: recurring-rule CRUD + single-pass spending breakdown"`

---

### Task 3: Formatting helpers + StoreError messages

**Files:**
- Create: `KharchaKit/Sources/KharchaKit/Math/AmountFormatter.swift`
- Modify: `KharchaKit/Sources/KharchaKit/Store/StoreError.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/AmountFormatterTests.swift`

**Interfaces:**
- Produces:
  - `enum AmountFormatter { static func krw(_ amount: Decimal) -> String }` — `₩` + en_US_POSIX decimal-grouped digits, 0–2 fraction digits (12000 → `"₩12,000"`, 12000.5 → `"₩12,000.5"`)
  - `Decimal.init(siriDouble: Double)` — converts a Siri `Double` parameter to `Decimal` rounded to 2 decimal places via string round-trip (12.35 stays exactly 12.35)
  - `StoreError: LocalizedError` — an `errorDescription` for every case (English literals; e.g. `.invalidAmount` → "That amount isn't valid.", `.notFound` → "I couldn't find that in Kharcha.", `.friendHasOpenDebts` → "That friend still has open debts.", `.cannotDeleteFallbackCategory` → "The Other category can't be deleted.", `.wrongDebtDirection` → "Only money you gave can be written off.", `.debtAlreadySettled` → "That debt is already settled.")

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func krwFormatsGroupedWithoutTrailingZeros() {
    #expect(AmountFormatter.krw(12_000) == "₩12,000")
    #expect(AmountFormatter.krw(Decimal(string: "12000.5")!) == "₩12,000.5")
    #expect(AmountFormatter.krw(0) == "₩0")
    #expect(AmountFormatter.krw(3_000_000) == "₩3,000,000")
}

@Test func siriDoubleConversionIsExactToTwoPlaces() {
    #expect(Decimal(siriDouble: 12.35) == Decimal(string: "12.35")!)
    #expect(Decimal(siriDouble: 12000) == Decimal(12000))
    #expect(Decimal(siriDouble: 0.1 + 0.2) == Decimal(string: "0.3")!)
}

@Test func storeErrorsHaveSpokenDescriptions() {
    for error: StoreError in [.invalidAmount, .notFound, .friendHasOpenDebts, .cannotDeleteFallbackCategory, .wrongDebtDirection, .debtAlreadySettled] {
        #expect(!(error.errorDescription ?? "").isEmpty)
    }
    #expect(StoreError.debtAlreadySettled.errorDescription == "That debt is already settled.")
}
```

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement.**

`Math/AmountFormatter.swift`:

```swift
import Foundation

public enum AmountFormatter {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    public static func krw(_ amount: Decimal) -> String {
        "₩" + (formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)")
    }
}

public extension Decimal {
    /// Siri hands amounts over as Double; round-trip through a 2-dp string so
    /// binary-float artifacts (12.35 → 12.34999…) never reach stored money.
    init(siriDouble: Double) {
        self = Decimal(string: String(format: "%.2f", siriDouble)) ?? Decimal(siriDouble)
        var rounded = self
        var copy = self
        NSDecimalRound(&rounded, &copy, 2, .plain)
        self = rounded.isZero ? 0 : rounded  // normalize -0
        // Trim trailing zeros by re-parsing a normalized description is unnecessary:
        // Decimal(string: "12000.00") == Decimal(12000) compares equal.
    }
}
```

`StoreError.swift`: add `import Foundation`, conform to `LocalizedError`, `public var errorDescription: String?` switch with the exact strings from Interfaces.

- [ ] **Step 4: Full suite green.**
- [ ] **Step 5: Commit** — `git commit -m "feat: KRW formatting, Siri Double→Decimal bridge, spoken StoreError messages"`

---

### Task 4: `IntentStoreProvider` + container factory

**Files:**
- Create: `KharchaKit/Sources/KharchaKit/Store/KharchaContainerFactory.swift`
- Create: `KharchaKit/Sources/KharchaKit/Intents/IntentStoreProvider.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/IntentStoreProviderTests.swift`

**Interfaces:**
- Produces:
  - `enum KharchaContainerFactory { static func appGroup(identifier: String = "group.com.manish.kharcha") throws -> ModelContainer; static func inMemory() throws -> ModelContainer }` — both build from `Schema(KharchaSchema.models)`
  - `enum IntentStoreProvider { static func store() throws -> ExpenseStore; static func override(container: ModelContainer); static func reset() }` — caches one container (NSLock-guarded); default factory is `appGroup()`; `override` injects a test/app container; repeated `store()` calls share the cached container (same data)

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
import SwiftData
@testable import KharchaKit

@Test func overriddenProviderSharesOneContainer() async throws {
    let container = try KharchaContainerFactory.inMemory()
    IntentStoreProvider.override(container: container)
    defer { IntentStoreProvider.reset() }

    let storeA = try IntentStoreProvider.store()
    let id = try await storeA.addTxn(amount: 500, kind: .expense, categoryID: nil, note: nil, date: .now, source: .siri)

    let storeB = try IntentStoreProvider.store()
    let rows = try await storeB.txnRows()
    #expect(rows.contains { $0.id == id })
}
```

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement.**

`Store/KharchaContainerFactory.swift`:

```swift
import Foundation
import SwiftData

public enum KharchaContainerFactory {
    public static let appGroupID = "group.com.manish.kharcha"

    public static func appGroup(identifier: String = appGroupID) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(KharchaSchema.models),
            configurations: [ModelConfiguration(groupContainer: .identifier(identifier))]
        )
    }

    public static func inMemory() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(KharchaSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}
```

`Intents/IntentStoreProvider.swift`:

```swift
import Foundation
import SwiftData

/// One shared container for every intent invocation (and injectable for tests/app).
public enum IntentStoreProvider {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: ModelContainer?

    public static func store() throws -> ExpenseStore {
        lock.lock(); defer { lock.unlock() }
        if cached == nil { cached = try KharchaContainerFactory.appGroup() }
        return ExpenseStore(modelContainer: cached!)
    }

    public static func override(container: ModelContainer) {
        lock.lock(); defer { lock.unlock() }
        cached = container
    }

    public static func reset() {
        lock.lock(); defer { lock.unlock() }
        cached = nil
    }
}
```

- [ ] **Step 4: Full suite green.**
- [ ] **Step 5: Commit** — `git commit -m "feat: shared intent store provider with injectable container"`

---

### Task 5: Log handlers — expense & income (with duplicate flow)

**Files:**
- Create: `KharchaKit/Sources/KharchaKit/Intents/Handlers/LogHandlers.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/LogHandlersTests.swift`

**Interfaces:**
- Produces:
  - `struct LogResult: Sendable, Equatable { public let txnID: UUID?; public let needsDuplicateConfirmation: Bool; public let message: String; public init(...) }`
  - `enum LogExpenseHandler { static func run(store: ExpenseStore, amount: Decimal, categoryID: UUID?, categoryName: String?, note: String?, now: Date, confirmedDuplicate: Bool) async throws -> LogResult }`
    - amount ≤ 0 → throws `.invalidAmount`
    - duplicate (per `store.isDuplicate`) and `confirmedDuplicate == false` → returns `txnID: nil, needsDuplicateConfirmation: true`, message "You just logged ₩X — log it again?"
    - otherwise saves with `source: .siri`, message "Logged ₩X for <categoryName ?? "Uncategorized">." (uses `AmountFormatter.krw`)
  - `enum LogIncomeHandler { static func run(store: ExpenseStore, amount: Decimal, note: String?, now: Date) async throws -> LogResult }` — saves income (source .siri), message "Recorded ₩X income."

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func logExpenseSavesAndSpeaks() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    let result = try await LogExpenseHandler.run(store: store, amount: 12_000, categoryID: food.id, categoryName: "Food", note: "lunch", now: d(2026, 8, 19), confirmedDuplicate: false)
    #expect(result.txnID != nil)
    #expect(!result.needsDuplicateConfirmation)
    #expect(result.message == "Logged ₩12,000 for Food.")
    let spent = try await store.spent(in: .today, categoryID: nil, now: d(2026, 8, 19), calendar: testCal)
    #expect(spent == 12_000)
}

@Test func duplicateAsksBeforeSavingTwice() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    let now = d(2026, 8, 19)
    _ = try await LogExpenseHandler.run(store: store, amount: 12_000, categoryID: food.id, categoryName: "Food", note: nil, now: now.addingTimeInterval(-30), confirmedDuplicate: false)

    let second = try await LogExpenseHandler.run(store: store, amount: 12_000, categoryID: food.id, categoryName: "Food", note: nil, now: now, confirmedDuplicate: false)
    #expect(second.needsDuplicateConfirmation)
    #expect(second.txnID == nil)

    let confirmed = try await LogExpenseHandler.run(store: store, amount: 12_000, categoryID: food.id, categoryName: "Food", note: nil, now: now, confirmedDuplicate: true)
    #expect(confirmed.txnID != nil)
    let spent = try await store.spent(in: .today, categoryID: nil, now: now, calendar: testCal)
    #expect(spent == 24_000)
}

@Test func logExpenseRejectsBadAmount() async throws {
    let store = try makeStore()
    await #expect(throws: StoreError.invalidAmount) {
        _ = try await LogExpenseHandler.run(store: store, amount: 0, categoryID: nil, categoryName: nil, note: nil, now: d(2026, 8, 19), confirmedDuplicate: false)
    }
}

@Test func logIncomeSaves() async throws {
    let store = try makeStore()
    let result = try await LogIncomeHandler.run(store: store, amount: 3_000_000, note: "salary", now: d(2026, 8, 19))
    #expect(result.message == "Recorded ₩3,000,000 income.")
    let income = try await store.income(in: .today, now: d(2026, 8, 19), calendar: testCal)
    #expect(income == 3_000_000)
}
```

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** `Intents/Handlers/LogHandlers.swift`:

```swift
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
```

- [ ] **Step 4: Full suite green.**
- [ ] **Step 5: Commit** — `git commit -m "feat: Siri log handlers — expense with duplicate confirmation, income"`

---

### Task 6: Query handlers — spending & budget

**Files:**
- Create: `KharchaKit/Sources/KharchaKit/Intents/Handlers/QueryHandlers.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/QueryHandlersTests.swift`

**Interfaces:**
- Produces:
  - `struct SpendingSummary: Sendable, Equatable { public let periodLabel: String; public let total: Decimal; public let top: [CategorySpend]; public let message: String; public init(...) }`
  - `enum SpendingQueryHandler { static func run(store: ExpenseStore, period: Period, categoryID: UUID?, categoryName: String?, now: Date, calendar: Calendar) async throws -> SpendingSummary }`
    - periodLabel: today → "today", week → "this week", month → "this month"
    - with categoryID: total = spent for that category; top = []; message "You spent ₩X on <name> <label>."
    - without: uses `spendingBreakdown`; top = first 3 categories; message "You spent ₩X <label>." (zero → "You haven't spent anything <label>.")
  - `struct BudgetReport: Sendable, Equatable { public let statuses: [BudgetStatus]; public let message: String; public init(...) }`
  - `enum BudgetStatusHandler { static func run(store: ExpenseStore, now: Date, calendar: Calendar) async throws -> BudgetReport }`
    - no budgets set → message "You haven't set any budgets yet."
    - all within → "All N budgets are on track."
    - K over → "K of N budgets are over: <names joined ', '>."

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func spendingSummaryOverall() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    _ = try await store.addTxn(amount: 42_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 19), source: .manual)
    _ = try await store.addTxn(amount: 700, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 19), source: .manual)

    let summary = try await SpendingQueryHandler.run(store: store, period: .today, categoryID: nil, categoryName: nil, now: d(2026, 8, 19, 20), calendar: testCal)
    #expect(summary.total == 42_700)
    #expect(summary.message == "You spent ₩42,700 today.")
    #expect(summary.top.first?.categoryName == "Food")
}

@Test func spendingSummaryForCategoryAndZeroSpend() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    let summary = try await SpendingQueryHandler.run(store: store, period: .week, categoryID: food.id, categoryName: "Food", now: d(2026, 8, 19), calendar: testCal)
    #expect(summary.total == 0)
    #expect(summary.message == "You haven't spent anything this week.")

    _ = try await store.addTxn(amount: 8_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 18), source: .manual)
    let summary2 = try await SpendingQueryHandler.run(store: store, period: .week, categoryID: food.id, categoryName: "Food", now: d(2026, 8, 19), calendar: testCal)
    #expect(summary2.message == "You spent ₩8,000 on Food this week.")
}

@Test func budgetReportMessages() async throws {
    let store = try makeStore()
    let empty = try await BudgetStatusHandler.run(store: store, now: d(2026, 8, 19), calendar: testCal)
    #expect(empty.message == "You haven't set any budgets yet.")

    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: 100_000)
    _ = try await store.addCategory(name: "Fun", symbol: "gamecontroller", colorHex: "#81B29A", monthlyBudget: 50_000)
    let ok = try await BudgetStatusHandler.run(store: store, now: d(2026, 8, 19), calendar: testCal)
    #expect(ok.message == "All 2 budgets are on track.")

    _ = try await store.addTxn(amount: 120_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 10), source: .manual)
    let over = try await BudgetStatusHandler.run(store: store, now: d(2026, 8, 19), calendar: testCal)
    #expect(over.message == "1 of 2 budgets are over: Food.")
    #expect(over.statuses.count == 2)
}
```

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** `Intents/Handlers/QueryHandlers.swift`:

```swift
import Foundation

public struct SpendingSummary: Sendable, Equatable {
    public let periodLabel: String
    public let total: Decimal
    public let top: [CategorySpend]
    public let message: String
    public init(periodLabel: String, total: Decimal, top: [CategorySpend], message: String) {
        self.periodLabel = periodLabel
        self.total = total
        self.top = top
        self.message = message
    }
}

public enum SpendingQueryHandler {
    public static func label(for period: Period) -> String {
        switch period {
        case .today: "today"
        case .week: "this week"
        case .month: "this month"
        }
    }

    public static func run(store: ExpenseStore, period: Period, categoryID: UUID?, categoryName: String?, now: Date, calendar: Calendar) async throws -> SpendingSummary {
        let periodLabel = label(for: period)
        if let categoryID {
            let total = try await store.spent(in: period, categoryID: categoryID, now: now, calendar: calendar)
            let message = total == 0
                ? "You haven't spent anything \(periodLabel)."
                : "You spent \(AmountFormatter.krw(total)) on \(categoryName ?? "that") \(periodLabel)."
            return SpendingSummary(periodLabel: periodLabel, total: total, top: [], message: message)
        }
        let breakdown = try await store.spendingBreakdown(in: period, now: now, calendar: calendar)
        let message = breakdown.total == 0
            ? "You haven't spent anything \(periodLabel)."
            : "You spent \(AmountFormatter.krw(breakdown.total)) \(periodLabel)."
        return SpendingSummary(periodLabel: periodLabel, total: breakdown.total, top: Array(breakdown.categories.prefix(3)), message: message)
    }
}

public struct BudgetReport: Sendable, Equatable {
    public let statuses: [BudgetStatus]
    public let message: String
    public init(statuses: [BudgetStatus], message: String) {
        self.statuses = statuses
        self.message = message
    }
}

public enum BudgetStatusHandler {
    public static func run(store: ExpenseStore, now: Date, calendar: Calendar) async throws -> BudgetReport {
        let statuses = try await store.budgetStatuses(now: now, calendar: calendar)
        guard !statuses.isEmpty else {
            return BudgetReport(statuses: [], message: "You haven't set any budgets yet.")
        }
        let over = statuses.filter(\.isOver)
        let message = over.isEmpty
            ? "All \(statuses.count) budgets are on track."
            : "\(over.count) of \(statuses.count) budgets are over: \(over.map(\.categoryName).joined(separator: ", "))."
        return BudgetReport(statuses: statuses, message: message)
    }
}
```

- [ ] **Step 4: Full suite green.**
- [ ] **Step 5: Commit** — `git commit -m "feat: Siri query handlers — spending summary and budget report"`

---

### Task 7: Debt & reminder handlers

**Files:**
- Create: `KharchaKit/Sources/KharchaKit/Intents/Handlers/DebtHandlers.swift`
- Create: `KharchaKit/Sources/KharchaKit/Intents/Handlers/ReminderHandler.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/DebtHandlersTests.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/ReminderHandlerTests.swift`

**Interfaces:**
- Produces:
  - `enum LogDebtHandler { static func run(store: ExpenseStore, friendID: UUID, friendName: String, amount: Decimal, direction: DebtDirection, note: String?, now: Date) async throws -> LogResult }`
    - message iGave: "Noted — <name> owes you ₩X (total ₩NET)." where NET = netBalance after saving
    - message iTook: "Noted — you owe <name> ₩X (total ₩|NET|)."
    - reuses `LogResult` (txnID carries the debt id; needsDuplicateConfirmation always false)
  - `struct SettleResult: Sendable, Equatable { public let settledAmount: Decimal; public let remainingOwed: Decimal; public let message: String; public init(...) }`
  - `enum SettleDebtHandler { static func run(store: ExpenseStore, friendID: UUID, friendName: String, amount: Decimal?, now: Date) async throws -> SettleResult }`
    - settles the friend's OPEN `.iGave` debts oldest-first; `amount == nil` → settle everything
    - no open iGave debts → throws `.notFound`
    - amount > total remaining → throws `.invalidAmount`
    - message full: "<name> is all settled up." / partial: "Settled ₩X — <name> still owes you ₩Y."
  - `struct DebtOverview: Sendable, Equatable { public let theyOweMe: [CategorySpend]; public let iOwe: [CategorySpend]; public let message: String; public init(...) }` (reuse `CategorySpend` as a generic name+amount row: categoryID nil, categoryName = friend name)
  - `enum DebtQueryHandler { static func run(store: ExpenseStore) async throws -> DebtOverview }`
    - per-friend net balances: positive → theyOweMe row, negative → iOwe row (absolute value); zero omitted; both lists sorted by amount descending
    - message: "No open debts." / "3 friends owe you ₩X in total." / "You owe ₩Y in total." / both: "Friends owe you ₩X; you owe ₩Y."
  - `enum AddReminderHandler { static func run(store: ExpenseStore, name: String, amount: Decimal, dayOfMonth: Int, remindDaysBefore: Int, now: Date, calendar: Calendar) async throws -> LogResult }`
    - creates rule (categoryID nil, autoLog false); message "I'll remind you about <name> (₩X) on <MMM d>." where the date is `RecurringMath.nextDueDate` formatted "MMM d" en_US_POSIX in `calendar`'s timezone

- [ ] **Step 1: Write the failing tests**

`DebtHandlersTests.swift`:

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func logDebtSpeaksNetBalance() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    let first = try await LogDebtHandler.run(store: store, friendID: ram.id, friendName: "Ram", amount: 50_000, direction: .iGave, note: nil, now: d(2026, 8, 19))
    #expect(first.message == "Noted — Ram owes you ₩50,000 (total ₩50,000).")
    let second = try await LogDebtHandler.run(store: store, friendID: ram.id, friendName: "Ram", amount: 80_000, direction: .iTook, note: nil, now: d(2026, 8, 19))
    #expect(second.message == "Noted — you owe Ram ₩80,000 (total ₩30,000).")
}

@Test func settleAllAndPartial() async throws {
    let store = try makeStore()
    let sita = try await store.addFriend(name: "Sita", phone: nil)
    _ = try await store.addDebt(friendID: sita.id, amount: 30_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)
    _ = try await store.addDebt(friendID: sita.id, amount: 20_000, direction: .iGave, date: d(2026, 8, 5), note: nil, dueDate: nil)

    let partial = try await SettleDebtHandler.run(store: store, friendID: sita.id, friendName: "Sita", amount: 40_000, now: d(2026, 8, 19))
    #expect(partial.settledAmount == 40_000)
    #expect(partial.remainingOwed == 10_000)
    #expect(partial.message == "Settled ₩40,000 — Sita still owes you ₩10,000.")

    let full = try await SettleDebtHandler.run(store: store, friendID: sita.id, friendName: "Sita", amount: nil, now: d(2026, 8, 19))
    #expect(full.message == "Sita is all settled up.")
    #expect(try await store.netBalance(friendID: sita.id) == 0)
}

@Test func settleValidation() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    await #expect(throws: StoreError.notFound) {
        _ = try await SettleDebtHandler.run(store: store, friendID: ram.id, friendName: "Ram", amount: nil, now: d(2026, 8, 19))
    }
    _ = try await store.addDebt(friendID: ram.id, amount: 10_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)
    await #expect(throws: StoreError.invalidAmount) {
        _ = try await SettleDebtHandler.run(store: store, friendID: ram.id, friendName: "Ram", amount: 10_001, now: d(2026, 8, 19))
    }
}

@Test func debtOverviewSplitsDirections() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    let sita = try await store.addFriend(name: "Sita", phone: nil)
    _ = try await store.addDebt(friendID: ram.id, amount: 50_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)
    _ = try await store.addDebt(friendID: sita.id, amount: 20_000, direction: .iTook, date: d(2026, 8, 5), note: nil, dueDate: nil)

    let overview = try await DebtQueryHandler.run(store: store)
    #expect(overview.theyOweMe.map(\.categoryName) == ["Ram"])
    #expect(overview.iOwe.first?.amount == 20_000)
    #expect(overview.message == "Friends owe you ₩50,000; you owe ₩20,000.")

    let empty = try await DebtQueryHandler.run(store: try makeStore())
    #expect(empty.message == "No open debts.")
}
```

`ReminderHandlerTests.swift`:

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func addReminderSpeaksNextDueDate() async throws {
    let store = try makeStore()
    let result = try await AddReminderHandler.run(store: store, name: "Rent", amount: 500_000, dayOfMonth: 25, remindDaysBefore: 3, now: d(2026, 8, 19), calendar: testCal)
    #expect(result.message == "I'll remind you about Rent (₩500,000) on Aug 25.")
    let rules = try await store.recurringRules()
    #expect(rules.count == 1)
    #expect(rules[0].dayOfMonth == 25)
}

@Test func addReminderRollsToNextMonth() async throws {
    let store = try makeStore()
    let result = try await AddReminderHandler.run(store: store, name: "Gym", amount: 60_000, dayOfMonth: 10, remindDaysBefore: 1, now: d(2026, 8, 19), calendar: testCal)
    #expect(result.message == "I'll remind you about Gym (₩60,000) on Sep 10.")
}
```

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement.**

`Intents/Handlers/DebtHandlers.swift`:

```swift
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
```

`Intents/Handlers/ReminderHandler.swift`:

```swift
import Foundation

public enum AddReminderHandler {
    public static func run(store: ExpenseStore, name: String, amount: Decimal, dayOfMonth: Int, remindDaysBefore: Int, now: Date, calendar: Calendar) async throws -> LogResult {
        let rule = try await store.addRecurringRule(name: name, amount: amount, categoryID: nil, dayOfMonth: dayOfMonth, remindDaysBefore: remindDaysBefore, autoLog: false)
        let due = RecurringMath.nextDueDate(dayOfMonth: dayOfMonth, after: now, calendar: calendar)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        return LogResult(
            txnID: rule.id,
            needsDuplicateConfirmation: false,
            message: "I'll remind you about \(name) (\(AmountFormatter.krw(amount))) on \(formatter.string(from: due))."
        )
    }
}
```

- [ ] **Step 4: Full suite green.**
- [ ] **Step 5: Commit** — `git commit -m "feat: Siri debt handlers (log/settle/overview) + reminder handler"`

---

### Task 8: Entities & enum — `CategoryEntity`, `FriendEntity`, `PeriodAppEnum`

**Files:**
- Create: `KharchaKit/Sources/KharchaKit/Intents/Entities/CategoryEntity.swift`
- Create: `KharchaKit/Sources/KharchaKit/Intents/Entities/FriendEntity.swift`
- Create: `KharchaKit/Sources/KharchaKit/Intents/Entities/PeriodAppEnum.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/EntityResolverTests.swift`

**Interfaces:**
- Produces:
  - `struct CategoryEntity: AppEntity` — `id: UUID`, `name: String`, `isFallback: Bool`; `EntityQuery` whose `entities(for:)` and `suggestedEntities()` delegate to a testable `CategoryEntityResolver`
  - `struct FriendEntity: AppEntity` — `id: UUID`, `name: String`; `EntityStringQuery` whose `entities(matching:)` delegates to `FriendEntityResolver` (which uses `FriendMatcher.rank`)
  - `enum PeriodAppEnum: String, AppEnum` — cases today/week/month; `var period: Period`
  - Testable resolvers (NO AppIntents imports): `enum CategoryEntityResolver { static func all(store:) async throws -> [CategorySnapshot]; static func matching(ids: [UUID], store:) async throws -> [CategorySnapshot] }`, `enum FriendEntityResolver { static func matching(_ query: String, store:) async throws -> [FriendSnapshot]; static func all(store:) async throws -> [FriendSnapshot]; static func matching(ids: [UUID], store:) async throws -> [FriendSnapshot] }`
  - Both queries obtain the store via `IntentStoreProvider.store()`.

- [ ] **Step 1: Write the failing tests** (resolvers only — AppIntents query plumbing is compile-verified):

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func categoryResolverReturnsAllAndByID() async throws {
    let store = try makeStore()
    try await store.seedDefaultCategoriesIfNeeded()
    let all = try await CategoryEntityResolver.all(store: store)
    #expect(all.count == 8)
    let food = all.first { $0.name == "Food" }!
    let byID = try await CategoryEntityResolver.matching(ids: [food.id, UUID()], store: store)
    #expect(byID.map(\.name) == ["Food"])
}

@Test func friendResolverUsesFuzzyRanking() async throws {
    let store = try makeStore()
    _ = try await store.addFriend(name: "Ramesh", phone: nil)
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    _ = try await store.addFriend(name: "Sita", phone: nil)

    let matches = try await FriendEntityResolver.matching("ram", store: store)
    #expect(matches.map(\.name) == ["Ram", "Ramesh"])
    let byID = try await FriendEntityResolver.matching(ids: [ram.id], store: store)
    #expect(byID.map(\.name) == ["Ram"])
    #expect(try await FriendEntityResolver.matching("xyz", store: store).isEmpty)
}

@Test func periodAppEnumMapsToPeriod() {
    #expect(PeriodAppEnum.today.period == .today)
    #expect(PeriodAppEnum.week.period == .week)
    #expect(PeriodAppEnum.month.period == .month)
}
```

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement.**

Resolvers (place at the top of the two entity files, before the AppIntents types):

```swift
public enum CategoryEntityResolver {
    public static func all(store: ExpenseStore) async throws -> [CategorySnapshot] {
        try await store.categories()
    }
    public static func matching(ids: [UUID], store: ExpenseStore) async throws -> [CategorySnapshot] {
        let wanted = Set(ids)
        return try await store.categories().filter { wanted.contains($0.id) }
    }
}

public enum FriendEntityResolver {
    public static func all(store: ExpenseStore) async throws -> [FriendSnapshot] {
        try await store.friends()
    }
    public static func matching(_ query: String, store: ExpenseStore) async throws -> [FriendSnapshot] {
        FriendMatcher.rank(query: query, candidates: try await store.friends())
    }
    public static func matching(ids: [UUID], store: ExpenseStore) async throws -> [FriendSnapshot] {
        let wanted = Set(ids)
        return try await store.friends().filter { wanted.contains($0.id) }
    }
}
```

AppIntents plumbing (same files, below the resolvers):

```swift
import AppIntents

public struct CategoryEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    public static let defaultQuery = CategoryEntityQuery()
    public var id: UUID
    public var name: String
    public var isFallback: Bool
    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    public init(snapshot: CategorySnapshot) {
        self.id = snapshot.id
        self.name = snapshot.name
        self.isFallback = snapshot.isFallback
    }
}

public struct CategoryEntityQuery: EntityQuery {
    public init() {}
    public func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        try await CategoryEntityResolver.matching(ids: identifiers, store: IntentStoreProvider.store()).map(CategoryEntity.init)
    }
    public func suggestedEntities() async throws -> [CategoryEntity] {
        try await CategoryEntityResolver.all(store: IntentStoreProvider.store()).map(CategoryEntity.init)
    }
}
```

`FriendEntity` mirrors this with `EntityStringQuery` (`entities(matching string: String)` → `FriendEntityResolver.matching`), `suggestedEntities()` → `all`.

`PeriodAppEnum.swift`:

```swift
import AppIntents

public enum PeriodAppEnum: String, AppEnum {
    case today, week, month
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Period"
    public static let caseDisplayRepresentations: [PeriodAppEnum: DisplayRepresentation] = [
        .today: "today", .week: "this week", .month: "this month"
    ]
    public var period: Period { Period(rawValue: rawValue) ?? .today }
}
```

If the SDK requires `static var` instead of `static let` for any AppEntity/AppEnum protocol witness, use what compiles — that's an allowed mechanical adaptation; record it in the report.

- [ ] **Step 4: Full suite green (`swift test` also compiles the AppIntents code).**
- [ ] **Step 5: Commit** — `git commit -m "feat: Siri entities — category/friend queries + period enum"`

---

### Task 9: The 8 AppIntent wrappers + snippet views

**Files:**
- Create: `KharchaKit/Sources/KharchaKit/Intents/KharchaIntents.swift` (all 8 intents)
- Create: `KharchaKit/Sources/KharchaKit/Snippets/KharchaSnippets.swift` (card views)
- Test: `KharchaKit/Tests/KharchaKitTests/IntentPerformTests.swift`

**Interfaces:**
- Produces the 8 public intents (spec §5): `LogExpenseIntent`, `LogIncomeIntent`, `SpendingQueryIntent`, `BudgetStatusIntent`, `AddReminderIntent`, `LogDebtIntent`, `SettleDebtIntent`, `DebtQueryIntent`.
- Common shape — each intent:
  - `static var title: LocalizedStringResource`, `static var description: IntentDescription`
  - Parameters via `@Parameter`; amounts are `Double` converted with `Decimal(siriDouble:)`; category/friend via the Task 8 entities; period via `PeriodAppEnum` (default `.today`)
  - `perform()` gets the store from `IntentStoreProvider.store()`, calls its handler with `Date()`/`Calendar.current`, and returns `.result(dialog: "\(result.message)")` — plus `ShowsSnippetView` with the matching card where a card exists
  - `LogExpenseIntent` duplicate flow: when the handler returns `needsDuplicateConfirmation`, call `try await requestConfirmation(...)` (use whichever overload the SDK offers — dialog text = handler's message), then re-run the handler with `confirmedDuplicate: true`
  - `LogDebtIntent` has a `direction` parameter via a small `DebtDirectionAppEnum: String, AppEnum` (cases `iGave` "I gave" / `iTook` "I took") defined in the same file
  - `SettleDebtIntent.amount` is `Double?` (nil = settle everything)
- Snippet views (SwiftUI, no external assets): `LogConfirmationCard(message: String)`, `SpendingCard(summary: SpendingSummary)` (total + top-3 rows), `BudgetCard(report: BudgetReport)` (name + progress bar per status, red when over), `DebtCard(overview: DebtOverview)` (two sections). Keep them small and theme-neutral (system colors only).
- Test coverage: direct `perform()` calls on the NON-interactive paths with `IntentStoreProvider.override(container:)` — LogIncomeIntent saves; SpendingQueryIntent returns (assert via store side-effect free call — just no-throw); LogExpenseIntent non-duplicate saves. Do NOT test the requestConfirmation path (needs a Siri context).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func logExpenseIntentPerformSaves() async throws {
    IntentStoreProvider.override(container: try KharchaContainerFactory.inMemory())
    defer { IntentStoreProvider.reset() }

    let intent = LogExpenseIntent()
    intent.amount = 12000
    intent.note = "lunch"
    _ = try await intent.perform()

    let store = try IntentStoreProvider.store()
    let rows = try await store.txnRows()
    #expect(rows.count == 1)
    #expect(rows[0].amount == 12_000)
    #expect(rows[0].source == .siri)
}

@Test func logIncomeIntentPerformSaves() async throws {
    IntentStoreProvider.override(container: try KharchaContainerFactory.inMemory())
    defer { IntentStoreProvider.reset() }

    let intent = LogIncomeIntent()
    intent.amount = 3_000_000
    _ = try await intent.perform()

    let store = try IntentStoreProvider.store()
    let rows = try await store.txnRows()
    #expect(rows.first?.kind == .income)
}

@Test func spendingQueryIntentPerformDoesNotThrowOnEmptyStore() async throws {
    IntentStoreProvider.override(container: try KharchaContainerFactory.inMemory())
    defer { IntentStoreProvider.reset() }
    let intent = SpendingQueryIntent()
    _ = try await intent.perform()  // default period .today, empty store → "haven't spent anything"
}
```

(If `@Parameter` wrapped properties reject direct assignment in tests, assign via the property wrapper's projected/underlying storage or construct with an initializer — record the mechanism used.)

- [ ] **Step 2: Run to verify failure** (types don't exist).
- [ ] **Step 3: Implement** `Intents/KharchaIntents.swift`. Reference shape for one logging intent and one query intent — replicate the pattern for all 8, wiring each to its Task 5–7 handler:

```swift
import AppIntents
import Foundation
import SwiftUI

public struct LogExpenseIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log Expense"
    public static let description = IntentDescription("Logs an expense in Kharcha.")

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

public struct SpendingQueryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Spending Summary"
    public static let description = IntentDescription("Tells you how much you've spent.")

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
```

Remaining six: `LogIncomeIntent` (amount, note? → LogIncomeHandler, LogConfirmationCard); `BudgetStatusIntent` (no params → BudgetStatusHandler, BudgetCard); `AddReminderIntent` (name String, amount Double, dayOfMonth Int, remindDaysBefore Int default 1 → AddReminderHandler, LogConfirmationCard); `LogDebtIntent` (friend FriendEntity, amount Double, direction DebtDirectionAppEnum, note String? → LogDebtHandler, LogConfirmationCard); `SettleDebtIntent` (friend FriendEntity, amount Double? → SettleDebtHandler, LogConfirmationCard); `DebtQueryIntent` (no params → DebtQueryHandler, DebtCard).

```swift
public enum DebtDirectionAppEnum: String, AppEnum {
    case iGave, iTook
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"
    public static let caseDisplayRepresentations: [DebtDirectionAppEnum: DisplayRepresentation] = [
        .iGave: "I gave", .iTook: "I took"
    ]
    public var direction: DebtDirection { self == .iGave ? .iGave : .iTook }
}
```

SDK-adaptation rule: `requestConfirmation` overloads and result-builder signatures for `ShowsSnippetView` vary between SDK releases. Adapt mechanically to what compiles (e.g. `requestConfirmation(output:)`, or returning `.result(dialog:view:)`), keep behavior identical, and record every adaptation in the report. Do NOT drop the duplicate-confirmation flow.

`Snippets/KharchaSnippets.swift` — small, self-contained SwiftUI:

```swift
import SwiftUI

public struct LogConfirmationCard: View {
    let message: String
    public init(message: String) { self.message = message }
    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(message).font(.callout)
            Spacer(minLength: 0)
        }
        .padding()
    }
}

public struct SpendingCard: View {
    let summary: SpendingSummary
    public init(summary: SpendingSummary) { self.summary = summary }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spent \(summary.periodLabel)").font(.caption).foregroundStyle(.secondary)
            Text(AmountFormatter.krw(summary.total)).font(.title2.bold())
            ForEach(summary.top, id: \.categoryName) { row in
                HStack {
                    Text(row.categoryName).font(.callout)
                    Spacer()
                    Text(AmountFormatter.krw(row.amount)).font(.callout.monospacedDigit())
                }
            }
        }
        .padding()
    }
}

public struct BudgetCard: View {
    let report: BudgetReport
    public init(report: BudgetReport) { self.report = report }
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(report.statuses, id: \.categoryID) { status in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(status.categoryName).font(.callout)
                        Spacer()
                        Text("\(AmountFormatter.krw(status.spent)) / \(AmountFormatter.krw(status.budget))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(status.isOver ? .red : .secondary)
                    }
                    ProgressView(value: min((status.spent as NSDecimalNumber).doubleValue, (status.budget as NSDecimalNumber).doubleValue),
                                 total: (status.budget as NSDecimalNumber).doubleValue)
                        .tint(status.isOver ? .red : .accentColor)
                }
            }
            if report.statuses.isEmpty { Text(report.message).font(.callout) }
        }
        .padding()
    }
}

public struct DebtCard: View {
    let overview: DebtOverview
    public init(overview: DebtOverview) { self.overview = overview }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !overview.theyOweMe.isEmpty {
                Text("Owed to you").font(.caption).foregroundStyle(.secondary)
                ForEach(overview.theyOweMe, id: \.categoryName) { row in
                    HStack { Text(row.categoryName); Spacer(); Text(AmountFormatter.krw(row.amount)).monospacedDigit() }
                        .font(.callout)
                }
            }
            if !overview.iOwe.isEmpty {
                Text("You owe").font(.caption).foregroundStyle(.secondary)
                ForEach(overview.iOwe, id: \.categoryName) { row in
                    HStack { Text(row.categoryName); Spacer(); Text(AmountFormatter.krw(row.amount)).monospacedDigit() }
                        .font(.callout)
                }
            }
            if overview.theyOweMe.isEmpty && overview.iOwe.isEmpty { Text("No open debts").font(.callout) }
        }
        .padding()
    }
}
```

- [ ] **Step 4: Full suite green** (`swift test` — also proves all AppIntents/SwiftUI code compiles for macOS; run `swift build` first if triaging compile errors is easier).
- [ ] **Step 5: Commit** — `git commit -m "feat: 8 Siri intents + snippet cards wired to handlers"`

---

## Done criteria for Plan 2

- `swift test` green (roughly 70 tests) from `KharchaKit/`.
- All 8 spec-§5 intents exist, each a thin wrapper over a tested handler.
- No handler imports AppIntents; no intent contains business logic.
- Parked Plan-1 item (isFallback backfill) closed by Task 1.

## What Plan 3 will consume from here

- The 8 intents + entities for its `AppShortcutsProvider` (phrases live in the app target — spec §5 phrase rules apply there).
- `KharchaContainerFactory.appGroup()` for the app + extension containers; `IntentStoreProvider.override(container:)` lets the app share its container with in-process intent execution.
- `RecurringRuleSnapshot`/`recurringRules()` for the Reminders screen; `SpendingBreakdown` for Home.
- Snippet views reusable in widgets later.
