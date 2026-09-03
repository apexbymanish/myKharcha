# myKharcha Architecture Guide

Use this alongside `PRODUCT_PRINCIPLES.md`. Principles tell you *why* decisions were made;
this document tells you *where* things live and what the rules are for each layer.

---

## Module Map — 39 modules total

### Layer 1 — Data: `Store/` (8 modules)

| Module | What it does | Rule |
|--------|-------------|------|
| `ExpenseStore` | SwiftData `@ModelActor` — all CRUD, all queries | Never does math; returns raw model data or typed snapshots |
| `ExpenseStoreInstallment` | Installment + payment CRUD extension | Extension on ExpenseStore; same actor |
| `ExpenseStoreSavings` | Savings pot + record CRUD extension | Extension on ExpenseStore; same actor |
| `ExpenseStoreSync` | Tombstone + conflict resolution (push/pull, upsert) | Newest-wins by `updatedAt`; actor-safe |
| `KharchaContainerFactory` | SwiftData container + shared App Group setup | Called once at app launch; not a singleton |
| `RecurringRuleSnapshot` | Value type read-model for RecurringRule | No logic, pure DTO |
| `DebtSnapshot` | Value type read-model for friend debt rows | No logic, pure DTO |
| `StoreError` | Typed errors for Store operations | Conforms to `LocalizedError` |

**What goes in Store:** `@Model` CRUD, `@Query` helpers, tombstone bookkeeping, upsert conflict resolution.  
**What does NOT go in Store:** arithmetic, formatting, sorting by score, business rules.

---

### Layer 2 — Business Logic: `Math/` (19 modules)

All modules in Math/ are **pure functions** — no I/O, no async, no SwiftUI. Fully unit-testable.

#### Planning engines (compute a plan from inputs)

| Module | Input → Output | Confusion risk |
|--------|---------------|---------------|
| `MonthlyPlanner` | income + commitments + savingsRate + typicalSpend → `MonthlyPlan` | None. Clear single purpose. |
| `PayCyclePlan` | salary + spent + cycleStart → `PayCyclePlan` | Name collision: the *struct* and the *planner* are both called `PayCyclePlan`. The struct IS the output — there is no separate `PayCyclePlanner` engine struct. The `PayCyclePlanner` is a free function in the same file. |
| `InstallmentMath` | monthlyAmount + termCount + payments + isClosed → `InstallmentStatus` | Clear. |
| `SavingsAllocator` | balance + [SavingsObligation] → `SavingsAllocation` | Clear. |

#### Query engines (slice historical data for display)

| Module | Purpose |
|--------|---------|
| `BudgetStatus` | Per-category over/under budget for current month |
| `SpendingBreakdown` | Category breakdown (donut chart data) |
| `ActivitySeries` | Bar chart bucketing — daily (week/month) or monthly (year) |

#### Date math utilities

| Module | Purpose | Confusion risk |
|--------|---------|---------------|
| `RecurringMath` | Next due date + reminder date for any `dayOfMonth` rule | Used by **both** RecurringRule (indefinite) **and** Installment (finite). This is intentional shared utility — do not split it. |
| `Period` | Siri/Intent time-period enum (day/week/month/year) | Lives in Math/ because Intents use it; not a view concern. |

#### Text parsing (Apple Intelligence boundary)

| Module | Role | Arithmetic? |
|--------|------|------------|
| `ExpenseTextParser` | Regex + NSDataDetector — parses amounts from text deterministically | No |
| `ExpenseTextExtractor` | Apple Intelligence wrapper — extracts amounts from payslips/messages | **No arithmetic — text I/O only.** Numbers come from the parser fallback if model is unavailable. |
| `PlanAdvisor` | Apple Intelligence — rephrases a plan summary in friendlier words | **No arithmetic — text I/O only.** Numbers are computed by MonthlyPlanner, PlanAdvisor only restyles. |
| `FriendMatcher` | Fuzzy name matching for friend debt entry via Siri | No |

#### Formatting & conversion

| Module | Purpose |
|--------|---------|
| `AmountFormatter` | `Decimal` → display string (currency, locale-aware) |
| `CurrencyConversion` | Apply an FX rate to a Decimal, rounding to minor units |

#### Background orchestration (async, but logic-light)

| Module | Purpose | Lives in Math/ because... |
|--------|---------|--------------------------|
| `AutoLogRunner` | Idempotently records due-today auto-log installments/rules | Pure orchestration, no UI dependency |
| `ReminderPlanner` | Converts rules + debts + installments into `[ReminderSpec]` | Pure function; `NotificationScheduler` (App layer) schedules them |

#### Export

| Module | Purpose |
|--------|---------|
| `CSVExporter` | Converts `[TxnRow]` to a CSV string |
| `CSVDocumentBuilder` | Wraps CSVExporter output into a `FileDocument` for Share Sheet |

---

### Layer 3 — Presentation: `ViewModels/` (12 modules)

ViewModels orchestrate Store + Math → publish `State` structs to views. They are `@MainActor`.

| ViewModel | Screen | Math modules called |
|-----------|--------|-------------------|
| `HomeViewModel` | Home | ActivitySeries, BudgetStatus |
| `MonthlyPlanViewModel` | Monthly Plan | MonthlyPlanner, SavingsAllocator, PlanAdvisor, ExpenseTextExtractor |
| `HistoryViewModel` | History | ActivitySeries |
| `InstallmentsViewModel` | Installments list | InstallmentMath (via store snapshots) |
| `BudgetsViewModel` | Budgets | BudgetStatus |
| `SavingsViewModel` | Savings | SavingsAllocator |
| `ImportViewModel` | Import | ExpenseTextParser, ExpenseTextExtractor |
| `TxnFormViewModel` | Add/Edit transaction | InstallmentMath (for installment mode) |
| `MonthlyPlanViewModel` | Monthly Plan | MonthlyPlanner, SavingsAllocator |
| `FriendsViewModel` | Friends list | — (store queries only) |
| `FriendDetailViewModel` | Friend settle/debt | FriendMatcher |

**Rule for ViewModels:** orchestrate; do not compute.  
Exceptions that are acceptable:  
- Sorting, filtering, prefix/prefix — presentation-layer decisions  
- `max(0, a - b)` on a pre-computed engine output — passthrough, not new math  
- Summing a `[Decimal]` into a total — only if no engine already exposes it

---

## Confusion Points (where developers get lost)

### 1. RecurringRule vs Installment — same mechanic, different lifecycle

| | RecurringRule | Installment |
|-|--------------|------------|
| Duration | Indefinite (rent, Netflix) | Finite, N months (car loan, EMI) |
| Balance | No balance tracked | Tracks remaining amount |
| Close | Delete the rule | Pay off / close |
| In Monthly Plan | Commitment | Commitment |
| In Reminders | Reminded on `dayOfMonth` | Reminded N days before due |

**Why confusing:** both have `dayOfMonth`, both appear as commitments in the plan. The difference is lifecycle. When in doubt: if a payment ends, it's an Installment; if it runs until you cancel, it's a RecurringRule.

### 2. PayCyclePlan (struct) vs MonthlyPlan (struct) — different time horizons

- `PayCyclePlan` = **short-term** (current pay cycle: days until payday, safe-to-spend today, is overspent?)
- `MonthlyPlan` = **medium-term** (this calendar month: can I afford my lifestyle? what to save?)

Both show on Home and Plan. They answer different questions. Do not merge them.

### 3. MonthlyPlanViewModel.averageMonthlyExpenses — async math in VM

This 9-line private function loops over 3 prior months of store queries to compute an average.  
It lives in the VM because it's async (needs `await store.spent(...)`) and pure engines are synchronous.  
**It is an acceptable exception** — the VM is aggregating I/O results, not inventing business logic.  
If it grows beyond averaging, extract to a Store method: `store.averageSpent(months: 3)`.

### 4. PlanCommitment appears in both MonthlyPlanner and ReminderPlanner

`PlanCommitment` is the shared value type representing one recurring obligation. It's defined in `MonthlyPlanner.swift` and also used by `ReminderPlanner` to schedule notifications.  
**Risk:** if you add a field to `PlanCommitment` for the planner, check if it affects reminder scheduling.

### 5. Debt (model) vs DebtRow (snapshot) vs FriendDebtChip (view)

- `Debt` = `@Model` (SwiftData)
- `DebtRow` (or `DebtSnapshot`) = value-type read-model for views
- `FriendDebtChip` = UI component

Three layers, one concept. This is correct layering — don't collapse them.

---

## Business Logic Rules (enforced)

1. **No arithmetic in Views.** Views display what ViewModels give them.
2. **No arithmetic in AI modules.** `ExpenseTextExtractor` and `PlanAdvisor` handle text only; amounts come from the engine.
3. **No SwiftData access in Math/.** Math engines receive value types (Decimal, Date, [T]) — never a `@Model`.
4. **No async in Math/.** Async lives in Store (actor) and ViewModel (MainActor). Math functions are synchronous.
5. **No presentation logic in Store.** Store returns raw rows or snapshots. Sorting for display is a ViewModel concern.
6. **Tombstone before delete.** Every deletion records a `Tombstone` so the sync engine can propagate the delete to other devices.

---

## What to do when you're unsure where code belongs

| Question | Answer |
|----------|--------|
| "Does this need SwiftData?" | → Store |
| "Is this a pure function of value types?" | → Math |
| "Does this need async + Store + Math glued together?" | → ViewModel |
| "Is this just displaying what the ViewModel gave me?" | → View |
| "Does this format a Decimal as a string?" | → AmountFormatter (Math) |
| "Does this compute a date from a dayOfMonth?" | → RecurringMath (Math) |
| "Does this talk to Apple Intelligence?" | → ExpenseTextExtractor or PlanAdvisor (Math), text only |
