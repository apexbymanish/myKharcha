# Kharcha — Personal Expense Tracker with Siri App Intents

**Date** 2026-08-14 · **Status** Approved design
**Owner** Manish Adhikari · **Device target** iPhone 15 Pro (iOS 27)

## 1. Purpose

A standalone personal iOS app to track daily expenses, income, budgets,
recurring bills (rent, subscriptions), and money lent to / borrowed from
friends — with first-class Siri support so logging and querying happen by
voice without opening the app.

Explicitly **not** in scope for v1:

- Bank SMS / notification auto-capture (iOS platform restriction; the user
  chose voice + manual entry instead)
- Receipt scanning, statement import
- Server / cloud sync (local only; the data model is designed so sync can be
  added later)
- Multi-user or family sharing

## 2. Decisions already made

| Decision | Choice | Why |
|---|---|---|
| Minimum iOS | **26.0** | Background intent modes + interactive Siri snippet cards; the only device is an iPhone 15 Pro on iOS 27 |
| Intent execution | **App Intents extension** (Approach B) | Apple-recommended: Siri responds with the app fully killed; fast and memory-light |
| Storage | **SwiftData in an App Group container** | Both app and extension open the same store; no sync code |
| Architecture | SwiftUI + MVVM, one SSOT `state` struct per screen | Matches the owner's team convention (GME `Modules2`), portable to TCA later |
| Language | Swift 6, SwiftUI only, no third-party dependencies | Personal app; keep it lean |
| Data location | Local only (v1) | "Local first, server later if it works" — models carry `id: UUID` + `updatedAt` so a sync layer can diff later |

## 3. Targets & project structure

```
Kharcha/
├── Kharcha.xcodeproj
├── KharchaKit/                   ← local SPM package, shared by both targets
│   ├── Models/                   # SwiftData @Model types
│   ├── Store/                    # ExpenseStore actor: all reads/writes
│   ├── Intents/                  # every AppIntent + entities + entity queries
│   └── Snippets/                 # SwiftUI views for Siri result cards
├── Kharcha/                      ← main app target (SwiftUI)
│   ├── App/                      # @main entry, AppShortcutsProvider (must live in app)
│   ├── Features/                 # Home, History, Budgets, Reminders, Friends, Settings
│   └── Resources/                # AppShortcuts.strings (en, ko, ne)
└── KharchaIntentsExtension/      ← App Intents extension target
    └── KharchaExtensionPackage.swift  # AppIntentsPackage → re-exports KharchaKit intents
```

- Intents are written **once** in `KharchaKit`. The extension executes them;
  the app registers phrases via `AppShortcutsProvider` + `AppIntentsPackage`.
  (Same pattern as GME's `GMESiriKit`/`GMEExtensionPackage`, clean from day one.)
- App Group: `group.com.manish.kharcha` on both targets.

## 4. Data model (SwiftData, App Group container)

All models have `id: UUID` and `updatedAt: Date`.

- **`Txn`** — `amount: Decimal`, `kind: .expense | .income`, `category: Category`,
  `note: String?`, `date: Date`, `source: .manual | .siri`
- **`Category`** — `name`, `symbol` (SF Symbol), `colorHex`,
  `monthlyBudget: Decimal?` (budget lives on the category — no separate model).
  Seeded defaults on first launch: Food, Transport, Rent, Subscriptions,
  Shopping, Health, Entertainment, Other.
- **`RecurringRule`** — `name` ("Rent"), `amount`, `category`, `dayOfMonth: Int`,
  `remindDaysBefore: Int`, `autoLog: Bool`
- **`Friend`** — `name`, `phone: String?`, `photoData: Data?` (picked from
  Contacts, stored locally, never uploaded)
- **`Debt`** — `friend: Friend`, `amount: Decimal`,
  `direction: .iGave | .iTook`, `date`, `note: String?`, `dueDate: Date?`,
  `settledAmount: Decimal` (partial repayment), `settled: Bool`

Rules:

- **`ExpenseStore`** (actor) is the only code that touches a `ModelContext`.
  Intents and ViewModels both call it. It exposes computed summaries
  (`spent(in: period, category:)`) — never cached totals.
- The container is created with
  `ModelConfiguration(groupContainer: .identifier("group.com.manish.kharcha"))`.
- Debts are **excluded** from spending/income stats. Money given is not
  "spent"; money taken is not income. A never-repaid debt can be converted to
  an expense with one tap (creates a `Txn`, marks the debt settled).

## 5. Siri intents catalog

All intents live in `KharchaKit`, execute in the extension, and run in
`.background` mode — the app never opens unless the user taps the result card.

| # | Intent | Example utterance | Parameters (Siri asks for missing) | Result |
|---|---|---|---|---|
| 1 | `LogExpenseIntent` | "Log 12,000 lunch in Kharcha" | amount, category (entity), note? | confirmation snippet |
| 2 | `LogIncomeIntent` | "I got paid 3 million in Kharcha" | amount, note? | confirmation snippet |
| 3 | `SpendingQueryIntent` | "How much did I spend today in Kharcha" | period (today/week/month), category? | interactive snippet: total + top 3 categories |
| 4 | `BudgetStatusIntent` | "How's my budget in Kharcha" | — | snippet: per-category bars, over-budget in red |
| 5 | `AddReminderIntent` | "Add rent reminder in Kharcha" | name, amount, day of month | confirmation snippet |
| 6 | `LogDebtIntent` | "I gave 50,000 to Ram in Kharcha" / "I took 20,000 from Sita in Kharcha" | direction, amount, friend (entity) | confirmation snippet |
| 7 | `SettleDebtIntent` | "Ram paid me back in Kharcha" | friend, amount (asks if partial) | snippet with remaining balance |
| 8 | `DebtQueryIntent` | "Who owes me money in Kharcha" | — | snippet: open debts, net totals |

8 App Shortcuts total — under Apple's limit of 10.

**Phrase rules (lessons from the GME iOS 27 findings, 2026-08-12):**

- Every phrase contains `\(.applicationName)` (Apple requirement).
- No payment trigger words — never "send money" (Apple Cash intercepts it).
  "log / spent / paid / gave / took" are safe.
- Every intent keeps at least one **parameter-free** phrase, because
  entity-parameter phrases only match after iOS snapshots the vocabulary
  (empty right after install → Siri falls back to "app not supported").
- Development-language phrases are English; Korean (and optionally Nepali) go
  in `<lang>.lproj/AppShortcuts.strings`, never mixed into the code array.
- `INAlternativeAppNames` in Info.plist: "Kharcha", plus a short alias if the
  full name mis-transcribes.

**Entity queries:** `CategoryEntity`, `FriendEntity`, `PeriodEntity` (enum).
`FriendEntity` reuses the fuzzy-match approach of GME's `RecipientMatcher`
(diacritic/space-insensitive contains + prefix ranking). Queries hit
`ExpenseStore` directly — local reads, no network, so the background entity
query problem GME had cannot occur.

## 6. App screens

1. **Home** — this month: income vs spent, budget bars, friends strip (net
   position per friend: "Ram owes you ₩50,000"), recent 10 transactions, big ➕
2. **Add/Edit sheet** — amount-first keypad, category grid, expense/income
   toggle, date, note
3. **History** — month sections, filter by category/kind, swipe to delete
4. **Budgets** — category list with monthly budget editing
5. **Reminders** — recurring rules; each schedules a
   `UNCalendarNotificationTrigger` `remindDaysBefore` days before `dayOfMonth`.
   Rules with `autoLog` insert the `Txn` automatically on the due date
   (checked on app launch and from the notification).
6. **Friends** — friend list with net balances; friend detail = full
   give/take/settle history; settle supports partial amounts
7. **Settings** — currency (default KRW), category management, export CSV

MVVM: each screen has one ViewModel with
`@Published private(set) var state` (SSOT), actions as methods.

## 7. Notifications

- Rent/subscription reminders and debt `dueDate` reminders share one
  scheduling engine in `KharchaKit` (`ReminderScheduler`).
- The app is the source of truth for scheduling; it resyncs all pending
  notifications on every launch. Intents that create rules/debts also schedule
  directly (allowed from extensions via `UNUserNotificationCenter`), with the
  app-launch resync as the safety net.

## 8. Error handling & edge cases

- Extension can't open the store → intent returns a spoken error
  ("Couldn't open your data — open Kharcha once"), never a silent failure.
- Amounts: `Decimal` from Siri natively; zero/negative rejected with re-prompt.
- Locked device: **logging allowed** (`authenticationPolicy` permissive),
  **queries require unlock** — totals and debt lists must not be readable from
  a locked phone.
- Duplicate voice log: identical amount+category within 2 minutes → Siri asks
  "You just logged this — again?"
- Deleting a Category with transactions → reassign to "Other" (never orphan).
- Deleting a Friend with open debts → blocked until debts are settled or
  converted.

## 9. Testing

- `KharchaKit` is a plain SPM package → `swift test` without booting the app.
  Unit tests: `ExpenseStore` summaries, budget math, recurring-rule date math
  (month ends, leap years), debt net-balance math, duplicate detection,
  friend fuzzy matching.
- Intent tests call `perform()` directly against an in-memory
  `ModelContainer`.
- Siri end-to-end is manual on-device (no simulator story worth automating —
  confirmed on the GME branch).

## 10. Later (explicitly deferred)

- CloudKit/own-server sync (models are ready: UUID + `updatedAt`)
- Widgets / Lock Screen controls (reuse the same intents)
- Spotlight indexing of transactions (`IndexedEntity`)
- Receipt scan, statement import
- TCA migration if ever desired
