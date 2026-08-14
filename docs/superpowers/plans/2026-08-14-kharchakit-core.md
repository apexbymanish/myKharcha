# KharchaKit Core Implementation Plan (Plan 1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `KharchaKit` — the shared SPM package holding all models, the data store, and every piece of business math for the Kharcha expense app — fully test-driven, green under `swift test`.

**Architecture:** Pure Swift Package (no Xcode project yet). SwiftData `@Model` classes + one `@ModelActor` store (`ExpenseStore`) that is the only code touching a `ModelContext`. All date/money math lives in small pure types tested in isolation. Tests use in-memory `ModelContainer`s and a fixed Gregorian/Asia-Seoul calendar.

**Tech Stack:** Swift 6.2 (tools 6.2), SwiftData, Swift Testing (`import Testing`), zero third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-14-kharcha-app-design.md`

## Global Constraints

- Platforms: `.iOS(.v26)`, `.macOS(.v26)` (macOS only so `swift test` runs locally).
- Money is always `Decimal`. Never `Double`.
- No third-party dependencies. `import Testing` for tests (not XCTest).
- Every model has `id: UUID` and `updatedAt: Date` (spec §4 — future sync).
- Debts are excluded from spending/income stats (spec §4).
- All store access goes through `ExpenseStore`; nothing else touches a `ModelContext`.
- SwiftData `#Predicate` with enums/Decimal is unreliable — fetch broadly, filter in memory (personal-scale data; this is a deliberate decision, don't "optimize" it).
- Tests must not depend on wall-clock time or the machine's timezone: every time-sensitive API takes `now: Date` and `calendar: Calendar` parameters.
- Commit after every task with the message given in the task.

**Working directory for all commands:** `~/Developer/Kharcha`

---

### Task 1: Package scaffold + smoke test

**Files:**
- Create: `KharchaKit/Package.swift`
- Create: `KharchaKit/Sources/KharchaKit/KharchaKit.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/SmokeTests.swift`

**Interfaces:**
- Produces: a package named `KharchaKit` that later tasks add sources/tests to. `swift test` runs from `KharchaKit/`.

- [ ] **Step 1: Create the package manifest**

`KharchaKit/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KharchaKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KharchaKit", targets: ["KharchaKit"])
    ],
    targets: [
        .target(name: "KharchaKit"),
        .testTarget(name: "KharchaKitTests", dependencies: ["KharchaKit"])
    ]
)
```

- [ ] **Step 2: Write the failing smoke test**

`KharchaKit/Tests/KharchaKitTests/SmokeTests.swift`:

```swift
import Testing
@testable import KharchaKit

@Test func packageLinks() {
    #expect(KharchaKitInfo.name == "KharchaKit")
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test`
Expected: FAIL — `cannot find 'KharchaKitInfo' in scope`

- [ ] **Step 4: Write minimal implementation**

`KharchaKit/Sources/KharchaKit/KharchaKit.swift`:

```swift
public enum KharchaKitInfo {
    public static let name = "KharchaKit"
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test`
Expected: PASS (1 test)

- [ ] **Step 6: Commit**

```bash
cd ~/Developer/Kharcha && git add KharchaKit && git commit -m "feat: scaffold KharchaKit SPM package with smoke test"
```

---

### Task 2: SwiftData models

**Files:**
- Create: `KharchaKit/Sources/KharchaKit/Models/Txn.swift`
- Create: `KharchaKit/Sources/KharchaKit/Models/Category.swift`
- Create: `KharchaKit/Sources/KharchaKit/Models/RecurringRule.swift`
- Create: `KharchaKit/Sources/KharchaKit/Models/Friend.swift`
- Create: `KharchaKit/Sources/KharchaKit/Models/Debt.swift`
- Create: `KharchaKit/Sources/KharchaKit/Models/KharchaSchema.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/ModelTests.swift`

**Interfaces:**
- Produces (exact — every later task uses these):
  - `enum TxnKind: String, Codable, Sendable { case expense, income }`
  - `enum TxnSource: String, Codable, Sendable { case manual, siri }`
  - `enum DebtDirection: String, Codable, Sendable { case iGave, iTook }`
  - `Txn(amount: Decimal, kind: TxnKind, category: Category?, note: String?, date: Date, source: TxnSource)`
  - `Category(name: String, symbol: String, colorHex: String, monthlyBudget: Decimal?)`
  - `RecurringRule(name: String, amount: Decimal, category: Category?, dayOfMonth: Int, remindDaysBefore: Int, autoLog: Bool)`
  - `Friend(name: String, phone: String?, photoData: Data?)`
  - `Debt(friend: Friend?, amount: Decimal, direction: DebtDirection, date: Date, note: String?, dueDate: Date?)` — starts with `settledAmount == 0`, `settled == false`
  - `Debt.remaining: Decimal` (computed: `amount - settledAmount`)
  - `KharchaSchema.models: [any PersistentModel.Type]` — the full model list for container setup

- [ ] **Step 1: Write the failing tests**

`KharchaKit/Tests/KharchaKitTests/ModelTests.swift`:

```swift
import Testing
import SwiftData
@testable import KharchaKit

@MainActor
@Test func modelsInsertIntoInMemoryContainer() throws {
    let container = try ModelContainer(
        for: Schema(KharchaSchema.models),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    let ctx = container.mainContext

    let food = Category(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: 300_000)
    ctx.insert(food)

    let txn = Txn(amount: 12_000, kind: .expense, category: food, note: "lunch", date: .now, source: .siri)
    ctx.insert(txn)

    let ram = Friend(name: "Ram", phone: nil, photoData: nil)
    ctx.insert(ram)

    let debt = Debt(friend: ram, amount: 50_000, direction: .iGave, date: .now, note: nil, dueDate: nil)
    ctx.insert(debt)

    let rent = RecurringRule(name: "Rent", amount: 500_000, category: food, dayOfMonth: 25, remindDaysBefore: 3, autoLog: true)
    ctx.insert(rent)

    try ctx.save()

    #expect(try ctx.fetch(FetchDescriptor<Txn>()).count == 1)
    #expect(try ctx.fetch(FetchDescriptor<Debt>()).first?.remaining == 50_000)
    #expect(try ctx.fetch(FetchDescriptor<Debt>()).first?.settled == false)
    #expect(txn.id != debt.id)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test`
Expected: FAIL — `cannot find 'KharchaSchema' in scope` (and the model types)

- [ ] **Step 3: Write the models**

`KharchaKit/Sources/KharchaKit/Models/Category.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class Category {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var colorHex: String
    public var monthlyBudget: Decimal?
    public var updatedAt: Date

    public init(name: String, symbol: String, colorHex: String, monthlyBudget: Decimal?) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.monthlyBudget = monthlyBudget
        self.updatedAt = .now
    }
}
```

`KharchaKit/Sources/KharchaKit/Models/Txn.swift`:

```swift
import Foundation
import SwiftData

public enum TxnKind: String, Codable, Sendable { case expense, income }
public enum TxnSource: String, Codable, Sendable { case manual, siri }

@Model
public final class Txn {
    public var id: UUID
    public var amount: Decimal
    public var kindRaw: String
    public var category: Category?
    public var note: String?
    public var date: Date
    public var sourceRaw: String
    public var updatedAt: Date

    public var kind: TxnKind {
        get { TxnKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }
    public var source: TxnSource {
        get { TxnSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public init(amount: Decimal, kind: TxnKind, category: Category?, note: String?, date: Date, source: TxnSource) {
        self.id = UUID()
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.category = category
        self.note = note
        self.date = date
        self.sourceRaw = source.rawValue
        self.updatedAt = .now
    }
}
```

`KharchaKit/Sources/KharchaKit/Models/RecurringRule.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class RecurringRule {
    public var id: UUID
    public var name: String
    public var amount: Decimal
    public var category: Category?
    public var dayOfMonth: Int
    public var remindDaysBefore: Int
    public var autoLog: Bool
    public var updatedAt: Date

    public init(name: String, amount: Decimal, category: Category?, dayOfMonth: Int, remindDaysBefore: Int, autoLog: Bool) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.category = category
        self.dayOfMonth = dayOfMonth
        self.remindDaysBefore = remindDaysBefore
        self.autoLog = autoLog
        self.updatedAt = .now
    }
}
```

`KharchaKit/Sources/KharchaKit/Models/Friend.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class Friend {
    public var id: UUID
    public var name: String
    public var phone: String?
    public var photoData: Data?
    public var updatedAt: Date

    public init(name: String, phone: String?, photoData: Data?) {
        self.id = UUID()
        self.name = name
        self.phone = phone
        self.photoData = photoData
        self.updatedAt = .now
    }
}
```

`KharchaKit/Sources/KharchaKit/Models/Debt.swift`:

```swift
import Foundation
import SwiftData

public enum DebtDirection: String, Codable, Sendable { case iGave, iTook }

@Model
public final class Debt {
    public var id: UUID
    public var friend: Friend?
    public var amount: Decimal
    public var directionRaw: String
    public var date: Date
    public var note: String?
    public var dueDate: Date?
    public var settledAmount: Decimal
    public var settled: Bool
    public var updatedAt: Date

    public var direction: DebtDirection {
        get { DebtDirection(rawValue: directionRaw) ?? .iGave }
        set { directionRaw = newValue.rawValue }
    }
    public var remaining: Decimal { amount - settledAmount }

    public init(friend: Friend?, amount: Decimal, direction: DebtDirection, date: Date, note: String?, dueDate: Date?) {
        self.id = UUID()
        self.friend = friend
        self.amount = amount
        self.directionRaw = direction.rawValue
        self.date = date
        self.note = note
        self.dueDate = dueDate
        self.settledAmount = 0
        self.settled = false
        self.updatedAt = .now
    }
}
```

`KharchaKit/Sources/KharchaKit/Models/KharchaSchema.swift`:

```swift
import SwiftData

public enum KharchaSchema {
    public static let models: [any PersistentModel.Type] = [
        Txn.self, Category.self, RecurringRule.self, Friend.self, Debt.self
    ]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/Kharcha && git add KharchaKit && git commit -m "feat: SwiftData models — Txn, Category, RecurringRule, Friend, Debt"
```

---

### Task 3: Period date-range math

**Files:**
- Create: `KharchaKit/Sources/KharchaKit/Math/Period.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/PeriodTests.swift`

**Interfaces:**
- Produces: `enum Period: String, CaseIterable, Sendable { case today, week, month }` with
  `func dateRange(now: Date, calendar: Calendar) -> Range<Date>`

- [ ] **Step 1: Write the failing tests**

`KharchaKit/Tests/KharchaKitTests/PeriodTests.swift`:

```swift
import Testing
import Foundation
@testable import KharchaKit

private var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    c.firstWeekday = 2 // Monday
    return c
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    cal.date(from: DateComponents(timeZone: cal.timeZone, year: y, month: m, day: d, hour: h))!
}

@Test func todayRangeCoversMidnightToMidnight() {
    let range = Period.today.dateRange(now: date(2026, 8, 14, 15), calendar: cal)
    #expect(range.lowerBound == date(2026, 8, 14, 0))
    #expect(range.upperBound == date(2026, 8, 15, 0))
}

@Test func weekRangeStartsMonday() {
    // 2026-08-14 is a Friday; week = Mon 08-10 ..< Mon 08-17
    let range = Period.week.dateRange(now: date(2026, 8, 14), calendar: cal)
    #expect(range.lowerBound == date(2026, 8, 10, 0))
    #expect(range.upperBound == date(2026, 8, 17, 0))
}

@Test func monthRangeCoversWholeMonth() {
    let range = Period.month.dateRange(now: date(2026, 8, 14), calendar: cal)
    #expect(range.lowerBound == date(2026, 8, 1, 0))
    #expect(range.upperBound == date(2026, 9, 1, 0))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test --filter PeriodTests`
Expected: FAIL — `cannot find 'Period' in scope`

- [ ] **Step 3: Write minimal implementation**

`KharchaKit/Sources/KharchaKit/Math/Period.swift`:

```swift
import Foundation

public enum Period: String, CaseIterable, Sendable {
    case today, week, month

    public func dateRange(now: Date, calendar: Calendar) -> Range<Date> {
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return start..<end
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: now)!
            return interval.start..<interval.end
        case .month:
            let interval = calendar.dateInterval(of: .month, for: now)!
            return interval.start..<interval.end
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/Kharcha && git add KharchaKit && git commit -m "feat: Period date-range math (today/week/month)"
```

---

### Task 4: ExpenseStore — transactions, spent/income summaries

**Files:**
- Create: `KharchaKit/Sources/KharchaKit/Store/ExpenseStore.swift`
- Create: `KharchaKit/Sources/KharchaKit/Store/StoreError.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/ExpenseStoreTests.swift`
- Test helper: `KharchaKit/Tests/KharchaKitTests/TestSupport.swift`

**Interfaces:**
- Produces (later tasks extend this same actor):
  - `@ModelActor actor ExpenseStore` created via `ExpenseStore(modelContainer:)`
  - `func addCategory(name: String, symbol: String, colorHex: String, monthlyBudget: Decimal?) throws -> CategorySnapshot`
  - `func addTxn(amount: Decimal, kind: TxnKind, categoryID: UUID?, note: String?, date: Date, source: TxnSource) throws -> UUID` — throws `StoreError.invalidAmount` for amount ≤ 0
  - `func spent(in period: Period, categoryID: UUID?, now: Date, calendar: Calendar) throws -> Decimal`
  - `func income(in period: Period, now: Date, calendar: Calendar) throws -> Decimal`
  - `enum StoreError: Error, Equatable { case invalidAmount, notFound, friendHasOpenDebts }`
  - Test helper: `func makeStore() throws -> ExpenseStore` (in-memory), `testCal` fixed calendar, `func d(_ y:Int,_ m:Int,_ day:Int,_ h:Int = 12) -> Date`

  **Note on IDs at the actor boundary:** model instances must not cross the actor boundary (Swift 6 sendability), so the store's public API takes and returns `UUID`s and value snapshots, never `@Model` objects. Read APIs return snapshot structs defined in the task where they appear.

- [ ] **Step 1: Write the shared test helper**

`KharchaKit/Tests/KharchaKitTests/TestSupport.swift`:

```swift
import Foundation
import SwiftData
@testable import KharchaKit

var testCal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    c.firstWeekday = 2
    return c
}

func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
    testCal.date(from: DateComponents(timeZone: testCal.timeZone, year: y, month: m, day: day, hour: h))!
}

func makeStore() throws -> ExpenseStore {
    let container = try ModelContainer(
        for: Schema(KharchaSchema.models),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    return ExpenseStore(modelContainer: container)
}
```

Also delete the now-redundant private helpers in `PeriodTests.swift` and switch it to `testCal` / `d(...)` (rename its `date(...)` calls to `d(...)`).

- [ ] **Step 2: Write the failing tests**

`KharchaKit/Tests/KharchaKitTests/ExpenseStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func spentSumsOnlyExpensesInPeriod() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)

    _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 14), source: .manual)
    _ = try await store.addTxn(amount: 8_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 14, 18), source: .siri)
    _ = try await store.addTxn(amount: 99_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 1), source: .manual)  // earlier in month
    _ = try await store.addTxn(amount: 3_000_000, kind: .income, categoryID: nil, note: "salary", date: d(2026, 8, 14), source: .manual) // income, excluded

    let today = try await store.spent(in: .today, categoryID: nil, now: d(2026, 8, 14, 20), calendar: testCal)
    #expect(today == 20_000)

    let month = try await store.spent(in: .month, categoryID: nil, now: d(2026, 8, 14, 20), calendar: testCal)
    #expect(month == 119_000)
}

@Test func spentFiltersByCategory() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    let transport = try await store.addCategory(name: "Transport", symbol: "bus", colorHex: "#3D405B", monthlyBudget: nil)

    _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 14), source: .manual)
    _ = try await store.addTxn(amount: 1_500, kind: .expense, categoryID: transport.id, note: nil, date: d(2026, 8, 14), source: .manual)

    let foodOnly = try await store.spent(in: .today, categoryID: food.id, now: d(2026, 8, 14, 20), calendar: testCal)
    #expect(foodOnly == 12_000)
}

@Test func incomeSumsOnlyIncome() async throws {
    let store = try makeStore()
    _ = try await store.addTxn(amount: 3_000_000, kind: .income, categoryID: nil, note: nil, date: d(2026, 8, 5), source: .manual)
    _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 5), source: .manual)

    let month = try await store.income(in: .month, now: d(2026, 8, 14), calendar: testCal)
    #expect(month == 3_000_000)
}

@Test func zeroOrNegativeAmountRejected() async throws {
    let store = try makeStore()
    await #expect(throws: StoreError.invalidAmount) {
        _ = try await store.addTxn(amount: 0, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 14), source: .siri)
    }
    await #expect(throws: StoreError.invalidAmount) {
        _ = try await store.addTxn(amount: -5, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 14), source: .siri)
    }
}
```

Note: `addCategory` returns a snapshot struct `CategorySnapshot` with `id`, `name`, `symbol`, `colorHex`, `monthlyBudget` (defined in Step 4) — that's what `.id` reads.

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test --filter ExpenseStoreTests`
Expected: FAIL — `cannot find 'ExpenseStore' in scope`

- [ ] **Step 4: Write minimal implementation**

`KharchaKit/Sources/KharchaKit/Store/StoreError.swift`:

```swift
public enum StoreError: Error, Equatable {
    case invalidAmount
    case notFound
    case friendHasOpenDebts
}
```

`KharchaKit/Sources/KharchaKit/Store/ExpenseStore.swift`:

```swift
import Foundation
import SwiftData

public struct CategorySnapshot: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let symbol: String
    public let colorHex: String
    public let monthlyBudget: Decimal?
}

@ModelActor
public actor ExpenseStore {

    // MARK: Categories

    @discardableResult
    public func addCategory(name: String, symbol: String, colorHex: String, monthlyBudget: Decimal?) throws -> CategorySnapshot {
        let category = Category(name: name, symbol: symbol, colorHex: colorHex, monthlyBudget: monthlyBudget)
        modelContext.insert(category)
        try modelContext.save()
        return snapshot(category)
    }

    // MARK: Transactions

    @discardableResult
    public func addTxn(amount: Decimal, kind: TxnKind, categoryID: UUID?, note: String?, date: Date, source: TxnSource) throws -> UUID {
        guard amount > 0 else { throw StoreError.invalidAmount }
        let category = try categoryID.flatMap { try fetchCategory(id: $0) }
        let txn = Txn(amount: amount, kind: kind, category: category, note: note, date: date, source: source)
        modelContext.insert(txn)
        try modelContext.save()
        return txn.id
    }

    public func spent(in period: Period, categoryID: UUID?, now: Date, calendar: Calendar) throws -> Decimal {
        try total(kind: .expense, period: period, categoryID: categoryID, now: now, calendar: calendar)
    }

    public func income(in period: Period, now: Date, calendar: Calendar) throws -> Decimal {
        try total(kind: .income, period: period, categoryID: nil, now: now, calendar: calendar)
    }

    // MARK: Internals

    private func total(kind: TxnKind, period: Period, categoryID: UUID?, now: Date, calendar: Calendar) throws -> Decimal {
        let range = period.dateRange(now: now, calendar: calendar)
        // Deliberate: fetch all, filter in memory. #Predicate + enum/Decimal is unreliable,
        // and this is personal-scale data. Do not "optimize" into a predicate.
        let txns = try modelContext.fetch(FetchDescriptor<Txn>())
        return txns
            .filter { $0.kind == kind && range.contains($0.date) }
            .filter { categoryID == nil || $0.category?.id == categoryID }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private func fetchCategory(id: UUID) throws -> Category? {
        try modelContext.fetch(FetchDescriptor<Category>()).first { $0.id == id }
    }

    private func snapshot(_ c: Category) -> CategorySnapshot {
        CategorySnapshot(id: c.id, name: c.name, symbol: c.symbol, colorHex: c.colorHex, monthlyBudget: c.monthlyBudget)
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test`
Expected: PASS (all tests)

- [ ] **Step 6: Commit**

```bash
cd ~/Developer/Kharcha && git add KharchaKit && git commit -m "feat: ExpenseStore actor — transactions + spent/income summaries"
```

---

### Task 5: Default categories seeding + budget status

**Files:**
- Modify: `KharchaKit/Sources/KharchaKit/Store/ExpenseStore.swift` (extend the actor)
- Create: `KharchaKit/Sources/KharchaKit/Math/BudgetStatus.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/BudgetTests.swift`

**Interfaces:**
- Consumes: `ExpenseStore`, `Period`, `CategorySnapshot` from Tasks 3–4.
- Produces:
  - `struct BudgetStatus: Sendable, Equatable { let categoryID: UUID; let categoryName: String; let spent: Decimal; let budget: Decimal; var isOver: Bool }`
  - `ExpenseStore.seedDefaultCategoriesIfNeeded() throws` — inserts the 8 spec categories only when the store has zero categories
  - `ExpenseStore.categories() throws -> [CategorySnapshot]` (sorted by name)
  - `ExpenseStore.setBudget(categoryID: UUID, amount: Decimal?) throws`
  - `ExpenseStore.budgetStatuses(now: Date, calendar: Calendar) throws -> [BudgetStatus]` — one entry per category **with a budget set**, month-to-date spend

- [ ] **Step 1: Write the failing tests**

`KharchaKit/Tests/KharchaKitTests/BudgetTests.swift`:

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func seedInsertsEightDefaultsOnce() async throws {
    let store = try makeStore()
    try await store.seedDefaultCategoriesIfNeeded()
    try await store.seedDefaultCategoriesIfNeeded() // idempotent
    let names = try await store.categories().map(\.name)
    #expect(names.count == 8)
    #expect(names.contains("Food"))
    #expect(names.contains("Rent"))
    #expect(names.contains("Other"))
}

@Test func budgetStatusReportsMonthToDateSpendAndOverrun() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: 100_000)
    let fun = try await store.addCategory(name: "Entertainment", symbol: "gamecontroller", colorHex: "#81B29A", monthlyBudget: 50_000)
    _ = try await store.addCategory(name: "NoBudget", symbol: "tag", colorHex: "#999999", monthlyBudget: nil)

    _ = try await store.addTxn(amount: 120_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 3), source: .manual)
    _ = try await store.addTxn(amount: 10_000, kind: .expense, categoryID: fun.id, note: nil, date: d(2026, 8, 10), source: .manual)
    _ = try await store.addTxn(amount: 999_999, kind: .expense, categoryID: fun.id, note: nil, date: d(2026, 7, 10), source: .manual) // last month

    let statuses = try await store.budgetStatuses(now: d(2026, 8, 14), calendar: testCal)
    #expect(statuses.count == 2) // only categories with budgets

    let foodStatus = statuses.first { $0.categoryName == "Food" }!
    #expect(foodStatus.spent == 120_000)
    #expect(foodStatus.isOver)

    let funStatus = statuses.first { $0.categoryName == "Entertainment" }!
    #expect(funStatus.spent == 10_000)
    #expect(!funStatus.isOver)
}

@Test func setBudgetUpdatesCategory() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    try await store.setBudget(categoryID: food.id, amount: 200_000)
    let statuses = try await store.budgetStatuses(now: d(2026, 8, 14), calendar: testCal)
    #expect(statuses.first?.budget == 200_000)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test --filter BudgetTests`
Expected: FAIL — `value of type 'ExpenseStore' has no member 'seedDefaultCategoriesIfNeeded'`

- [ ] **Step 3: Write minimal implementation**

`KharchaKit/Sources/KharchaKit/Math/BudgetStatus.swift`:

```swift
import Foundation

public struct BudgetStatus: Sendable, Equatable {
    public let categoryID: UUID
    public let categoryName: String
    public let spent: Decimal
    public let budget: Decimal
    public var isOver: Bool { spent > budget }

    public init(categoryID: UUID, categoryName: String, spent: Decimal, budget: Decimal) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.spent = spent
        self.budget = budget
    }
}
```

Append inside `ExpenseStore` (same file, `// MARK: Categories` region):

```swift
    public static let defaultCategories: [(name: String, symbol: String, colorHex: String)] = [
        ("Food", "fork.knife", "#E07A5F"),
        ("Transport", "bus", "#3D405B"),
        ("Rent", "house", "#8E7DBE"),
        ("Subscriptions", "arrow.triangle.2.circlepath", "#5F797B"),
        ("Shopping", "bag", "#F2CC8F"),
        ("Health", "cross.case", "#81B29A"),
        ("Entertainment", "gamecontroller", "#E5989B"),
        ("Other", "tag", "#9A9A9A")
    ]

    public func seedDefaultCategoriesIfNeeded() throws {
        guard try modelContext.fetch(FetchDescriptor<Category>()).isEmpty else { return }
        for c in Self.defaultCategories {
            modelContext.insert(Category(name: c.name, symbol: c.symbol, colorHex: c.colorHex, monthlyBudget: nil))
        }
        try modelContext.save()
    }

    public func categories() throws -> [CategorySnapshot] {
        try modelContext.fetch(FetchDescriptor<Category>())
            .sorted { $0.name < $1.name }
            .map(snapshot)
    }

    public func setBudget(categoryID: UUID, amount: Decimal?) throws {
        guard let category = try fetchCategory(id: categoryID) else { throw StoreError.notFound }
        category.monthlyBudget = amount
        category.updatedAt = .now
        try modelContext.save()
    }

    public func budgetStatuses(now: Date, calendar: Calendar) throws -> [BudgetStatus] {
        try modelContext.fetch(FetchDescriptor<Category>())
            .compactMap { category in
                guard let budget = category.monthlyBudget else { return nil }
                let spent = try? self.spent(in: .month, categoryID: category.id, now: now, calendar: calendar)
                return BudgetStatus(categoryID: category.id, categoryName: category.name, spent: spent ?? 0, budget: budget)
            }
            .sorted { $0.categoryName < $1.categoryName }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/Kharcha && git add KharchaKit && git commit -m "feat: default category seeding + monthly budget statuses"
```

---

### Task 6: Recurring-rule date math

**Files:**
- Create: `KharchaKit/Sources/KharchaKit/Math/RecurringMath.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/RecurringMathTests.swift`

**Interfaces:**
- Produces:
  - `enum RecurringMath` with
    - `static func nextDueDate(dayOfMonth: Int, after date: Date, calendar: Calendar) -> Date` — strictly after `date`, clamped to month length (31 → Feb 28/29), at start-of-day
    - `static func reminderDate(for due: Date, daysBefore: Int, calendar: Calendar) -> Date`

- [ ] **Step 1: Write the failing tests**

`KharchaKit/Tests/KharchaKitTests/RecurringMathTests.swift`:

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func nextDueLaterThisMonth() {
    let due = RecurringMath.nextDueDate(dayOfMonth: 25, after: d(2026, 8, 14), calendar: testCal)
    #expect(due == d(2026, 8, 25, 0))
}

@Test func nextDueRollsToNextMonthWhenPassed() {
    let due = RecurringMath.nextDueDate(dayOfMonth: 10, after: d(2026, 8, 14), calendar: testCal)
    #expect(due == d(2026, 9, 10, 0))
}

@Test func nextDueOnSameDayRollsForward() {
    // "after" is strict: on the 25th at noon, day-25 rule points at next month
    let due = RecurringMath.nextDueDate(dayOfMonth: 25, after: d(2026, 8, 25), calendar: testCal)
    #expect(due == d(2026, 9, 25, 0))
}

@Test func day31ClampsToShortMonths() {
    let due = RecurringMath.nextDueDate(dayOfMonth: 31, after: d(2026, 9, 1), calendar: testCal)
    #expect(due == d(2026, 9, 30, 0))
}

@Test func day31ClampsToFebruary() {
    let due = RecurringMath.nextDueDate(dayOfMonth: 31, after: d(2027, 2, 1), calendar: testCal)
    #expect(due == d(2027, 2, 28, 0))
}

@Test func day31ClampsToLeapFebruary() {
    let due = RecurringMath.nextDueDate(dayOfMonth: 31, after: d(2028, 2, 1), calendar: testCal)
    #expect(due == d(2028, 2, 29, 0))
}

@Test func reminderDateSubtractsDays() {
    let reminder = RecurringMath.reminderDate(for: d(2026, 8, 25, 0), daysBefore: 3, calendar: testCal)
    #expect(reminder == d(2026, 8, 22, 0))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test --filter RecurringMathTests`
Expected: FAIL — `cannot find 'RecurringMath' in scope`

- [ ] **Step 3: Write minimal implementation**

`KharchaKit/Sources/KharchaKit/Math/RecurringMath.swift`:

```swift
import Foundation

public enum RecurringMath {

    /// First occurrence of `dayOfMonth` strictly after `date`, clamped to the
    /// target month's length (31 → Feb 28/29), at start-of-day.
    public static func nextDueDate(dayOfMonth: Int, after date: Date, calendar: Calendar) -> Date {
        let startOfMonth = calendar.dateInterval(of: .month, for: date)!.start
        var candidate = clamped(dayOfMonth: dayOfMonth, inMonthOf: startOfMonth, calendar: calendar)
        if candidate <= calendar.startOfDay(for: date) {
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
            candidate = clamped(dayOfMonth: dayOfMonth, inMonthOf: nextMonth, calendar: calendar)
        }
        return candidate
    }

    public static func reminderDate(for due: Date, daysBefore: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -daysBefore, to: due)!
    }

    private static func clamped(dayOfMonth: Int, inMonthOf monthStart: Date, calendar: Calendar) -> Date {
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)!.count
        let day = min(dayOfMonth, dayCount)
        return calendar.date(byAdding: .day, value: day - 1, to: calendar.startOfDay(for: monthStart))!
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/Kharcha && git add KharchaKit && git commit -m "feat: recurring-rule date math with month-end clamping"
```

---

### Task 7: Debts — log, net balance, settle (partial)

**Files:**
- Modify: `KharchaKit/Sources/KharchaKit/Store/ExpenseStore.swift` (extend the actor)
- Create: `KharchaKit/Sources/KharchaKit/Store/DebtSnapshot.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/DebtTests.swift`

**Interfaces:**
- Consumes: models from Task 2, `ExpenseStore` from Task 4.
- Produces:
  - `struct FriendSnapshot: Sendable, Equatable { let id: UUID; let name: String }`
  - `struct DebtSnapshot: Sendable, Equatable { let id: UUID; let friendID: UUID?; let friendName: String; let amount: Decimal; let direction: DebtDirection; let remaining: Decimal; let settled: Bool; let dueDate: Date? }`
  - `ExpenseStore.addFriend(name: String, phone: String?) throws -> FriendSnapshot`
  - `ExpenseStore.friends() throws -> [FriendSnapshot]`
  - `ExpenseStore.addDebt(friendID: UUID, amount: Decimal, direction: DebtDirection, date: Date, note: String?, dueDate: Date?) throws -> DebtSnapshot` — throws `StoreError.invalidAmount` for ≤ 0, `StoreError.notFound` for unknown friend
  - `ExpenseStore.settleDebt(debtID: UUID, amount: Decimal) throws -> DebtSnapshot` — partial settle allowed; `settled` flips when `remaining == 0`; over-settle throws `StoreError.invalidAmount`
  - `ExpenseStore.openDebts() throws -> [DebtSnapshot]` (unsettled only, oldest first)
  - `ExpenseStore.netBalance(friendID: UUID) throws -> Decimal` — positive = they owe me (`iGave` remaining − `iTook` remaining)

- [ ] **Step 1: Write the failing tests**

`KharchaKit/Tests/KharchaKitTests/DebtTests.swift`:

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func netBalanceCombinesGaveAndTook() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)

    _ = try await store.addDebt(friendID: ram.id, amount: 50_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)
    _ = try await store.addDebt(friendID: ram.id, amount: 20_000, direction: .iTook, date: d(2026, 8, 5), note: nil, dueDate: nil)

    let net = try await store.netBalance(friendID: ram.id)
    #expect(net == 30_000) // Ram owes me 30,000
}

@Test func partialSettleReducesRemaining() async throws {
    let store = try makeStore()
    let sita = try await store.addFriend(name: "Sita", phone: nil)
    let debt = try await store.addDebt(friendID: sita.id, amount: 50_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)

    let afterPartial = try await store.settleDebt(debtID: debt.id, amount: 20_000)
    #expect(afterPartial.remaining == 30_000)
    #expect(!afterPartial.settled)

    let afterFull = try await store.settleDebt(debtID: debt.id, amount: 30_000)
    #expect(afterFull.remaining == 0)
    #expect(afterFull.settled)

    let net = try await store.netBalance(friendID: sita.id)
    #expect(net == 0)
}

@Test func overSettleThrows() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    let debt = try await store.addDebt(friendID: ram.id, amount: 10_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)

    await #expect(throws: StoreError.invalidAmount) {
        _ = try await store.settleDebt(debtID: debt.id, amount: 10_001)
    }
}

@Test func debtsDoNotAffectSpendingOrIncome() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    _ = try await store.addDebt(friendID: ram.id, amount: 50_000, direction: .iGave, date: d(2026, 8, 14), note: nil, dueDate: nil)
    _ = try await store.addDebt(friendID: ram.id, amount: 20_000, direction: .iTook, date: d(2026, 8, 14), note: nil, dueDate: nil)

    let spent = try await store.spent(in: .month, categoryID: nil, now: d(2026, 8, 14), calendar: testCal)
    let income = try await store.income(in: .month, now: d(2026, 8, 14), calendar: testCal)
    #expect(spent == 0)
    #expect(income == 0)
}

@Test func openDebtsListsUnsettledOldestFirst() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    let old = try await store.addDebt(friendID: ram.id, amount: 10_000, direction: .iGave, date: d(2026, 7, 1), note: nil, dueDate: nil)
    _ = try await store.addDebt(friendID: ram.id, amount: 20_000, direction: .iTook, date: d(2026, 8, 1), note: nil, dueDate: nil)
    _ = try await store.settleDebt(debtID: old.id, amount: 10_000)

    let open = try await store.openDebts()
    #expect(open.count == 1)
    #expect(open.first?.amount == 20_000)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test --filter DebtTests`
Expected: FAIL — `value of type 'ExpenseStore' has no member 'addFriend'`

- [ ] **Step 3: Write minimal implementation**

`KharchaKit/Sources/KharchaKit/Store/DebtSnapshot.swift`:

```swift
import Foundation

public struct FriendSnapshot: Sendable, Equatable {
    public let id: UUID
    public let name: String
}

public struct DebtSnapshot: Sendable, Equatable {
    public let id: UUID
    public let friendID: UUID?
    public let friendName: String
    public let amount: Decimal
    public let direction: DebtDirection
    public let remaining: Decimal
    public let settled: Bool
    public let dueDate: Date?
}
```

Append inside `ExpenseStore`:

```swift
    // MARK: Friends & Debts

    @discardableResult
    public func addFriend(name: String, phone: String?) throws -> FriendSnapshot {
        let friend = Friend(name: name, phone: phone, photoData: nil)
        modelContext.insert(friend)
        try modelContext.save()
        return FriendSnapshot(id: friend.id, name: friend.name)
    }

    public func friends() throws -> [FriendSnapshot] {
        try modelContext.fetch(FetchDescriptor<Friend>())
            .sorted { $0.name < $1.name }
            .map { FriendSnapshot(id: $0.id, name: $0.name) }
    }

    @discardableResult
    public func addDebt(friendID: UUID, amount: Decimal, direction: DebtDirection, date: Date, note: String?, dueDate: Date?) throws -> DebtSnapshot {
        guard amount > 0 else { throw StoreError.invalidAmount }
        guard let friend = try fetchFriend(id: friendID) else { throw StoreError.notFound }
        let debt = Debt(friend: friend, amount: amount, direction: direction, date: date, note: note, dueDate: dueDate)
        modelContext.insert(debt)
        try modelContext.save()
        return snapshot(debt)
    }

    @discardableResult
    public func settleDebt(debtID: UUID, amount: Decimal) throws -> DebtSnapshot {
        guard let debt = try fetchDebt(id: debtID) else { throw StoreError.notFound }
        guard amount > 0, amount <= debt.remaining else { throw StoreError.invalidAmount }
        debt.settledAmount += amount
        debt.settled = debt.remaining == 0
        debt.updatedAt = .now
        try modelContext.save()
        return snapshot(debt)
    }

    public func openDebts() throws -> [DebtSnapshot] {
        try modelContext.fetch(FetchDescriptor<Debt>())
            .filter { !$0.settled }
            .sorted { $0.date < $1.date }
            .map(snapshot)
    }

    /// Positive = the friend owes me; negative = I owe the friend.
    public func netBalance(friendID: UUID) throws -> Decimal {
        try modelContext.fetch(FetchDescriptor<Debt>())
            .filter { $0.friend?.id == friendID && !$0.settled }
            .reduce(Decimal(0)) { sum, debt in
                switch debt.direction {
                case .iGave: sum + debt.remaining
                case .iTook: sum - debt.remaining
                }
            }
    }

    private func fetchFriend(id: UUID) throws -> Friend? {
        try modelContext.fetch(FetchDescriptor<Friend>()).first { $0.id == id }
    }

    private func fetchDebt(id: UUID) throws -> Debt? {
        try modelContext.fetch(FetchDescriptor<Debt>()).first { $0.id == id }
    }

    private func snapshot(_ debt: Debt) -> DebtSnapshot {
        DebtSnapshot(
            id: debt.id,
            friendID: debt.friend?.id,
            friendName: debt.friend?.name ?? "?",
            amount: debt.amount,
            direction: debt.direction,
            remaining: debt.remaining,
            settled: debt.settled,
            dueDate: debt.dueDate
        )
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/Kharcha && git add KharchaKit && git commit -m "feat: friend debts — log, partial settle, net balance"
```

---

### Task 8: Convert unpaid debt to expense

**Files:**
- Modify: `KharchaKit/Sources/KharchaKit/Store/ExpenseStore.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/DebtConversionTests.swift`

**Interfaces:**
- Consumes: `addDebt`/`settleDebt`/`spent` from Tasks 4 & 7; `seedDefaultCategoriesIfNeeded` + "Other" category from Task 5.
- Produces:
  - `ExpenseStore.convertDebtToExpense(debtID: UUID, date: Date) throws -> UUID` — creates a `Txn` (kind `.expense`, category "Other", note `"Unpaid: <friend name>"`, source `.manual`) for the debt's **remaining** amount, marks the debt fully settled, returns the new Txn id. Only valid for `.iGave` debts; `.iTook` throws `StoreError.invalidAmount`. Already-settled debt throws `StoreError.notFound`.

- [ ] **Step 1: Write the failing tests**

`KharchaKit/Tests/KharchaKitTests/DebtConversionTests.swift`:

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func convertMakesExpenseOfRemainingAndSettles() async throws {
    let store = try makeStore()
    try await store.seedDefaultCategoriesIfNeeded()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    let debt = try await store.addDebt(friendID: ram.id, amount: 50_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)
    _ = try await store.settleDebt(debtID: debt.id, amount: 20_000) // partially repaid

    _ = try await store.convertDebtToExpense(debtID: debt.id, date: d(2026, 8, 14))

    let spent = try await store.spent(in: .month, categoryID: nil, now: d(2026, 8, 14), calendar: testCal)
    #expect(spent == 30_000) // only the unpaid remainder becomes an expense

    let open = try await store.openDebts()
    #expect(open.isEmpty)

    let net = try await store.netBalance(friendID: ram.id)
    #expect(net == 0)
}

@Test func convertTookDebtIsRejected() async throws {
    let store = try makeStore()
    try await store.seedDefaultCategoriesIfNeeded()
    let sita = try await store.addFriend(name: "Sita", phone: nil)
    let debt = try await store.addDebt(friendID: sita.id, amount: 20_000, direction: .iTook, date: d(2026, 8, 1), note: nil, dueDate: nil)

    await #expect(throws: StoreError.invalidAmount) {
        _ = try await store.convertDebtToExpense(debtID: debt.id, date: d(2026, 8, 14))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test --filter DebtConversionTests`
Expected: FAIL — `value of type 'ExpenseStore' has no member 'convertDebtToExpense'`

- [ ] **Step 3: Write minimal implementation**

Append inside `ExpenseStore` (Friends & Debts region):

```swift
    /// Give up on an unpaid debt: the remaining amount becomes a real expense
    /// (category "Other") and the debt is closed.
    @discardableResult
    public func convertDebtToExpense(debtID: UUID, date: Date) throws -> UUID {
        guard let debt = try fetchDebt(id: debtID), !debt.settled else { throw StoreError.notFound }
        guard debt.direction == .iGave else { throw StoreError.invalidAmount }

        let other = try modelContext.fetch(FetchDescriptor<Category>()).first { $0.name == "Other" }
        let txn = Txn(
            amount: debt.remaining,
            kind: .expense,
            category: other,
            note: "Unpaid: \(debt.friend?.name ?? "?")",
            date: date,
            source: .manual
        )
        modelContext.insert(txn)
        debt.settledAmount = debt.amount
        debt.settled = true
        debt.updatedAt = .now
        try modelContext.save()
        return txn.id
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/Kharcha && git add KharchaKit && git commit -m "feat: convert unpaid debt remainder to expense"
```

---

### Task 9: Friend fuzzy matcher

**Files:**
- Create: `KharchaKit/Sources/KharchaKit/Math/FriendMatcher.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/FriendMatcherTests.swift`

**Interfaces:**
- Produces:
  - `enum FriendMatcher` with
    - `static func normalize(_ s: String) -> String` — lowercased, diacritics folded, whitespace removed
    - `static func rank(query: String, candidates: [FriendSnapshot]) -> [FriendSnapshot]` — exact-normalized match first, then prefix matches, then contains matches; empty query or no match → `[]`
- This is the Siri entity-query backbone for Plan 2 (`FriendEntity`), same idea as GME's `RecipientMatcher`.

- [ ] **Step 1: Write the failing tests**

`KharchaKit/Tests/KharchaKitTests/FriendMatcherTests.swift`:

```swift
import Testing
import Foundation
@testable import KharchaKit

private func f(_ name: String) -> FriendSnapshot { FriendSnapshot(id: UUID(), name: name) }

@Test func normalizeFoldsCaseDiacriticsAndSpaces() {
    #expect(FriendMatcher.normalize("  Rám Pŕasad ") == "ramprasad")
}

@Test func exactBeatsPrefixBeatsContains() {
    let ram = f("Ram")
    let ramesh = f("Ramesh")
    let biram = f("Biram")
    let ranked = FriendMatcher.rank(query: "ram", candidates: [biram, ramesh, ram])
    #expect(ranked.map(\.name) == ["Ram", "Ramesh", "Biram"])
}

@Test func noMatchReturnsEmpty() {
    #expect(FriendMatcher.rank(query: "xyz", candidates: [f("Ram")]).isEmpty)
    #expect(FriendMatcher.rank(query: "", candidates: [f("Ram")]).isEmpty)
}

@Test func koreanNamesMatchByPrefix() {
    let ranked = FriendMatcher.rank(query: "김", candidates: [f("이수민"), f("김민수")])
    #expect(ranked.map(\.name) == ["김민수"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test --filter FriendMatcherTests`
Expected: FAIL — `cannot find 'FriendMatcher' in scope`

- [ ] **Step 3: Write minimal implementation**

`KharchaKit/Sources/KharchaKit/Math/FriendMatcher.swift`:

```swift
import Foundation

public enum FriendMatcher {

    public static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { !$0.isWhitespace }
    }

    /// Exact-normalized match first, then prefix, then contains.
    public static func rank(query: String, candidates: [FriendSnapshot]) -> [FriendSnapshot] {
        let q = normalize(query)
        guard !q.isEmpty else { return [] }

        func score(_ name: String) -> Int? {
            let n = normalize(name)
            if n == q { return 0 }
            if n.hasPrefix(q) { return 1 }
            if n.contains(q) { return 2 }
            return nil
        }

        return candidates
            .compactMap { c in score(c.name).map { (c, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/Kharcha && git add KharchaKit && git commit -m "feat: FriendMatcher fuzzy ranking for Siri entity queries"
```

---

### Task 10: Duplicate voice-log detection

**Files:**
- Modify: `KharchaKit/Sources/KharchaKit/Store/ExpenseStore.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/DuplicateTests.swift`

**Interfaces:**
- Consumes: `addTxn` from Task 4.
- Produces:
  - `ExpenseStore.isDuplicate(amount: Decimal, categoryID: UUID?, now: Date) throws -> Bool` — true when a `.siri`-sourced expense with the same amount and category exists within the last 120 seconds. Plan 2's `LogExpenseIntent` calls this before saving and asks "You just logged this — again?"

- [ ] **Step 1: Write the failing tests**

`KharchaKit/Tests/KharchaKitTests/DuplicateTests.swift`:

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func sameAmountCategoryWithin2MinutesIsDuplicate() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    let now = d(2026, 8, 14, 12)

    _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: food.id, note: nil,
                               date: now.addingTimeInterval(-60), source: .siri)

    #expect(try await store.isDuplicate(amount: 12_000, categoryID: food.id, now: now))
    #expect(try await store.isDuplicate(amount: 13_000, categoryID: food.id, now: now) == false)   // different amount
    #expect(try await store.isDuplicate(amount: 12_000, categoryID: nil, now: now) == false)       // different category
    #expect(try await store.isDuplicate(amount: 12_000, categoryID: food.id,
                                        now: now.addingTimeInterval(600)) == false)                // too old
}

@Test func manualEntriesNeverCountAsDuplicates() async throws {
    let store = try makeStore()
    let now = d(2026, 8, 14, 12)
    _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: nil, note: nil,
                               date: now.addingTimeInterval(-30), source: .manual)
    #expect(try await store.isDuplicate(amount: 12_000, categoryID: nil, now: now) == false)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test --filter DuplicateTests`
Expected: FAIL — `value of type 'ExpenseStore' has no member 'isDuplicate'`

- [ ] **Step 3: Write minimal implementation**

Append inside `ExpenseStore` (Transactions region):

```swift
    /// True when an identical Siri-logged expense (same amount + category)
    /// exists within the last 120 seconds — used by LogExpenseIntent to
    /// re-prompt instead of double-logging.
    public func isDuplicate(amount: Decimal, categoryID: UUID?, now: Date) throws -> Bool {
        let cutoff = now.addingTimeInterval(-120)
        return try modelContext.fetch(FetchDescriptor<Txn>()).contains {
            $0.source == .siri
                && $0.kind == .expense
                && $0.amount == amount
                && $0.category?.id == categoryID
                && $0.date > cutoff && $0.date <= now
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/Kharcha && git add KharchaKit && git commit -m "feat: duplicate detection for Siri-logged expenses (2-minute window)"
```

---

### Task 11: Delete rules — category reassignment, friend blocking

**Files:**
- Modify: `KharchaKit/Sources/KharchaKit/Store/ExpenseStore.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/DeleteRulesTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `ExpenseStore.deleteCategory(categoryID: UUID) throws` — reassigns that category's Txns and RecurringRules to "Other" first (creating "Other" if missing); deleting "Other" itself throws `StoreError.invalidAmount`
  - `ExpenseStore.deleteFriend(friendID: UUID) throws` — throws `StoreError.friendHasOpenDebts` when any unsettled debt references the friend; otherwise deletes friend and their settled debts
  - `ExpenseStore.deleteTxn(txnID: UUID) throws`

- [ ] **Step 1: Write the failing tests**

`KharchaKit/Tests/KharchaKitTests/DeleteRulesTests.swift`:

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func deleteCategoryReassignsTxnsToOther() async throws {
    let store = try makeStore()
    try await store.seedDefaultCategoriesIfNeeded()
    let cats = try await store.categories()
    let food = cats.first { $0.name == "Food" }!
    let other = cats.first { $0.name == "Other" }!

    _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 14), source: .manual)
    try await store.deleteCategory(categoryID: food.id)

    let otherSpend = try await store.spent(in: .month, categoryID: other.id, now: d(2026, 8, 14), calendar: testCal)
    #expect(otherSpend == 12_000)
    #expect(try await store.categories().contains { $0.name == "Food" } == false)
}

@Test func deletingOtherIsRejected() async throws {
    let store = try makeStore()
    try await store.seedDefaultCategoriesIfNeeded()
    let other = try await store.categories().first { $0.name == "Other" }!
    await #expect(throws: StoreError.invalidAmount) {
        try await store.deleteCategory(categoryID: other.id)
    }
}

@Test func deleteFriendBlockedByOpenDebt() async throws {
    let store = try makeStore()
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    let debt = try await store.addDebt(friendID: ram.id, amount: 10_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)

    await #expect(throws: StoreError.friendHasOpenDebts) {
        try await store.deleteFriend(friendID: ram.id)
    }

    _ = try await store.settleDebt(debtID: debt.id, amount: 10_000)
    try await store.deleteFriend(friendID: ram.id) // now allowed
    #expect(try await store.friends().isEmpty)
}

@Test func deleteTxnRemovesIt() async throws {
    let store = try makeStore()
    let id = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 14), source: .manual)
    try await store.deleteTxn(txnID: id)
    let spent = try await store.spent(in: .month, categoryID: nil, now: d(2026, 8, 14), calendar: testCal)
    #expect(spent == 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test --filter DeleteRulesTests`
Expected: FAIL — `value of type 'ExpenseStore' has no member 'deleteCategory'`

- [ ] **Step 3: Write minimal implementation**

Append inside `ExpenseStore`:

```swift
    // MARK: Deletion rules

    public func deleteCategory(categoryID: UUID) throws {
        guard let category = try fetchCategory(id: categoryID) else { throw StoreError.notFound }
        guard category.name != "Other" else { throw StoreError.invalidAmount }

        let other = try ensureOtherCategory()
        for txn in try modelContext.fetch(FetchDescriptor<Txn>()) where txn.category?.id == categoryID {
            txn.category = other
            txn.updatedAt = .now
        }
        for rule in try modelContext.fetch(FetchDescriptor<RecurringRule>()) where rule.category?.id == categoryID {
            rule.category = other
            rule.updatedAt = .now
        }
        modelContext.delete(category)
        try modelContext.save()
    }

    public func deleteFriend(friendID: UUID) throws {
        guard let friend = try fetchFriend(id: friendID) else { throw StoreError.notFound }
        let debts = try modelContext.fetch(FetchDescriptor<Debt>()).filter { $0.friend?.id == friendID }
        guard debts.allSatisfy(\.settled) else { throw StoreError.friendHasOpenDebts }
        for debt in debts { modelContext.delete(debt) }
        modelContext.delete(friend)
        try modelContext.save()
    }

    public func deleteTxn(txnID: UUID) throws {
        guard let txn = try modelContext.fetch(FetchDescriptor<Txn>()).first(where: { $0.id == txnID }) else {
            throw StoreError.notFound
        }
        modelContext.delete(txn)
        try modelContext.save()
    }

    private func ensureOtherCategory() throws -> Category {
        if let other = try modelContext.fetch(FetchDescriptor<Category>()).first(where: { $0.name == "Other" }) {
            return other
        }
        let other = Category(name: "Other", symbol: "tag", colorHex: "#9A9A9A", monthlyBudget: nil)
        modelContext.insert(other)
        return other
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/Kharcha && git add KharchaKit && git commit -m "feat: deletion rules — category reassign to Other, friend delete gating"
```

---

### Task 12: CSV export

**Files:**
- Create: `KharchaKit/Sources/KharchaKit/Math/CSVExporter.swift`
- Modify: `KharchaKit/Sources/KharchaKit/Store/ExpenseStore.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/CSVExportTests.swift`

**Interfaces:**
- Consumes: `addTxn`/`addCategory` from Tasks 4–5.
- Produces:
  - `struct TxnRow: Sendable, Equatable { let date: Date; let kind: TxnKind; let amount: Decimal; let categoryName: String; let note: String? }`
  - `enum CSVExporter { static func export(_ rows: [TxnRow], timeZone: TimeZone) -> String }` — header `date,kind,amount,category,note`; ISO-8601 dates (`yyyy-MM-dd`); fields containing comma/quote/newline are double-quoted with `""` escaping
  - `ExpenseStore.txnRows() throws -> [TxnRow]` (all transactions, oldest first; category name `""` when nil)

- [ ] **Step 1: Write the failing tests**

`KharchaKit/Tests/KharchaKitTests/CSVExportTests.swift`:

```swift
import Testing
import Foundation
@testable import KharchaKit

@Test func exportProducesHeaderAndEscapedRows() {
    let rows = [
        TxnRow(date: d(2026, 8, 14), kind: .expense, amount: 12_000, categoryName: "Food", note: "lunch, with Ram"),
        TxnRow(date: d(2026, 8, 15), kind: .income, amount: 3_000_000, categoryName: "", note: nil)
    ]
    let csv = CSVExporter.export(rows, timeZone: testCal.timeZone)
    let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(lines[0] == "date,kind,amount,category,note")
    #expect(lines[1] == #"2026-08-14,expense,12000,Food,"lunch, with Ram""#)
    #expect(lines[2] == "2026-08-15,income,3000000,,")
}

@Test func quotesInsideFieldsAreDoubled() {
    let rows = [TxnRow(date: d(2026, 8, 14), kind: .expense, amount: 1, categoryName: "Food", note: #"say "hi""#)]
    let csv = CSVExporter.export(rows, timeZone: testCal.timeZone)
    #expect(csv.contains(#""say ""hi""""#))
}

@Test func storeExportsAllTxnsOldestFirst() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    _ = try await store.addTxn(amount: 2_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 14), source: .manual)
    _ = try await store.addTxn(amount: 1_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 1), source: .siri)

    let rows = try await store.txnRows()
    #expect(rows.map(\.amount) == [1_000, 2_000])
    #expect(rows[1].categoryName == "Food")
    #expect(rows[0].categoryName == "")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test --filter CSVExportTests`
Expected: FAIL — `cannot find 'TxnRow' in scope`

- [ ] **Step 3: Write minimal implementation**

`KharchaKit/Sources/KharchaKit/Math/CSVExporter.swift`:

```swift
import Foundation

public struct TxnRow: Sendable, Equatable {
    public let date: Date
    public let kind: TxnKind
    public let amount: Decimal
    public let categoryName: String
    public let note: String?

    public init(date: Date, kind: TxnKind, amount: Decimal, categoryName: String, note: String?) {
        self.date = date
        self.kind = kind
        self.amount = amount
        self.categoryName = categoryName
        self.note = note
    }
}

public enum CSVExporter {

    public static func export(_ rows: [TxnRow], timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var lines = ["date,kind,amount,category,note"]
        for row in rows {
            lines.append([
                formatter.string(from: row.date),
                row.kind.rawValue,
                "\(row.amount)",
                escape(row.categoryName),
                escape(row.note ?? "")
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
```

Append inside `ExpenseStore` (Transactions region):

```swift
    public func txnRows() throws -> [TxnRow] {
        try modelContext.fetch(FetchDescriptor<Txn>())
            .sorted { $0.date < $1.date }
            .map { TxnRow(date: $0.date, kind: $0.kind, amount: $0.amount, categoryName: $0.category?.name ?? "", note: $0.note) }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test`
Expected: PASS (all tests)

- [ ] **Step 5: Final full run + commit**

Run: `cd ~/Developer/Kharcha/KharchaKit && swift test`
Expected: PASS — every test in the package green.

```bash
cd ~/Developer/Kharcha && git add KharchaKit && git commit -m "feat: CSV export for transactions"
```

---

## Done criteria for Plan 1

- `swift test` green from `KharchaKit/` with all 12 tasks' tests.
- No third-party dependencies in `Package.swift`.
- `ExpenseStore` is the only file importing `SwiftData` outside `Models/`.

## What Plans 2 & 3 will consume from here

- Plan 2 (Siri intents): `ExpenseStore` API surface (all snapshot-based, Sendable), `FriendMatcher.rank`, `Period`, `isDuplicate`, `BudgetStatus`.
- Plan 3 (App + extension): `KharchaSchema.models` for the App Group container, `RecurringMath` for `ReminderScheduler`, `CSVExporter` for Settings export.
