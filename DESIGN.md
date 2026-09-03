# Kharcha — Design System & Product Principles

Kharcha (branded **myKharcha**) is a local‑first personal finance app for iOS. This
document is the single source of truth for **why it looks and behaves the way it
does** — the principles, the design system, the interaction patterns, and the
honest gaps.

The north star: **"Less, but better."** Money apps earn trust by being calm,
legible, and honest — never by decoration. Brand defers to content; the engine is
authoritative about every number; nothing nags.

---

## 1. Design lineage (the shoulders we stand on)

Kharcha's decisions trace to three well‑established bodies of work:

- **Dieter Rams — Ten Principles of Good Design** ("Weniger, aber besser").
  The ones we optimize hardest for: *understandable, unobtrusive, honest, thorough
  to the last detail, and as little design as possible.*
- **Don Norman — usability fundamentals** (*The Design of Everyday Things*):
  discoverability, feedback, a clear conceptual model, affordances/signifiers,
  natural mapping, and error‑preventing constraints.
- **Apple Human Interface Guidelines — Clarity · Deference · Depth**, which
  encodes much of the above into concrete iOS rules (single accent, semantic
  color, system materials, Dynamic Type, VoiceOver).

---

## 2. Product principles (what we actually hold ourselves to)

1. **Honest numbers.** The tested **engine (KharchaKit) computes every monetary
   figure**. Apple Intelligence only *reads* input text and *rewrites* output
   text — it never does arithmetic. A wrong number must be impossible.
2. **One source of truth for money.** Actions create real `Txn`s. Forecasts
   (Monthly Plan, installment commitments) are *projections* layered on top and
   never double‑count actual spending.
3. **Effortless common path, powerful rare path.** The 95% case (log a one‑time
   expense) is the fastest thing on screen; advanced flows (installments, loans)
   sit one tap away via **progressive disclosure**.
4. **Don't force login; don't nag.** Everything works offline on‑device without an
   account. Sign‑in (for backup/sync) is offered once, dismissibly.
5. **Not color‑alone.** Every color meaning is paired with text or a glyph
   (color‑blind + VoiceOver safe).
6. **Localized & region‑aware by default.** UI in en/ko/ne; currency and dates
   follow the user's locale/selection.
7. **Least design possible.** A single accent, system neutrals, no gratuitous
   chrome or motion.

---

## 3. Information architecture

**Tab bar (core destinations, HIG: keep to a few):**

| Tab | Purpose |
|-----|---------|
| **Home** | At‑a‑glance balance, this‑week trend, month breakdown, budgets, friends, recent activity, quick add/import. |
| **History** | The full ledger + **Activity charts** (bar chart, calendar heat grid, net indicator). |
| **Friends** | People you lend to / borrow from; per‑friend debt detail. |
| **More** | Secondary tools, **sectioned** so it isn't a junk drawer. |

**More is grouped, not enumerated** (each row has an SF icon + one‑line description, Settings‑style):
- **Planning:** Monthly Plan · Budgets · Savings · Installments & Loans · Reminders
- **Account:** Settings

**Layered discovery** (so users rarely hunt): *create* in Add Expense →
*monitor* on Home / Monthly Plan → *manage* on the dedicated screen.

---

## 4. Color

A brand identity derived from the app logo (teal → green), applied per HIG so
**brand defers to content**.

| Token | Light | Dark | Use |
|-------|-------|------|-----|
| `brandPrimary` (accent) | `#0B7167` | `#33D1BF` | App tint: tabs, buttons, links, pickers, hero gradient start |
| `brandSecondary` | `#12854B` | `#45D98A` | Hero gradient end (logo green) |
| `moneyIn` | `#008033` | `#4CD963` | Income / "owes you" / net gain |
| `moneyOut` | `#CC000D` | `#FF6B61` | Expense / over‑budget / errors / net loss |
| Backgrounds | system | system | `Color(.systemBackground)` etc. — never hardcoded |
| Text | `.primary` / `.secondary` | adaptive | All copy |

Rules:
- **One accent, used consistently** for interactivity everywhere — no competing
  per‑screen accents. `brandPrimary` is both the asset‑catalog **AccentColor**
  (`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`) and applied via
  `.tint(.brandPrimary)` at the tab root.
- **Green/red are signals, not branding** — only on amounts and status.
- **Neutrals dominate;** brand color is used sparingly (hero + accent).
- **Adaptive in both modes** (deep in light so white clears 4.5:1 on the hero;
  brighter in dark). Category hues are floored for legibility on dark.

---

## 5. Typography & numerals

- **Text styles only** (`.largeTitle`, `.headline`, `.caption`, …) so **Dynamic
  Type** scales everything; no fixed point sizes for body copy.
- **Money uses `.monospacedDigit()`** so columns of amounts align; the balance
  hero and the Add‑screen amount use `.rounded` design for a friendly, fintech feel.
- Amounts are formatted through `AmountFormatter` (currency `FormatStyle`,
  locale/selection‑aware), never hand‑built.

---

## 6. Components (reusable, brand‑aware)

- **`BalanceHeroCard`** — the branded balance card anchoring Home (teal→green
  gradient, 22pt corners, soft brand shadow; "Spent this month" as the headline,
  income beneath). One combined VoiceOver element.
- **`ActivitySummaryHeader`** — Received · Spent · **Net** with an up/down arrow
  and green/red color (instant "am I ahead or losing?").
- **`ActivityBarChart` / `MiniTrendChart`** — Swift Charts spend‑vs‑income bars
  (Week/Month/Year); the mini variant is the compact Home trend.
- **`MonthHeatGrid`** — month calendar tinted by daily net; tap a day to filter.
- **`SpendingDonutChart`** — month‑by‑category donut, colored to match chips.
- **`CategoryChip`** — filled when selected; hue from the category.
- **`MoreRow`** — icon + title + subtitle rows for the More list.
- **`StatBlock`, `InlineError`, `BudgetBar`, `FriendDebtChip`, `TxnRowView`,
  `PayCycleCard`, `EmptyStateView`, `BackupPromptCard`** — shared building blocks.

---

## 7. Interaction patterns

- **Amount‑first entry.** Add Transaction leads with a large, auto‑focused amount;
  Expense/Income is the primary control; category grid is **filtered by kind**
  (no income categories under Expense) with a clear selected state.
- **Progressive disclosure.** "Split into monthly installments" reveals the
  installment/loan flow only when needed; one‑time stays the default.
- **Feedback + reversibility.** Tapping a calendar day filters the list with a
  "Showing 24 Aug — tap to show all" chip; swipe‑to‑delete everywhere; deleting an
  installment payment reverses its expense.
- **Sensible defaults & guards.** Income field starts empty (avoids the ×10
  concatenation bug); duplicate categories auto‑merge; keyboards get a Done button
  on decimal pads.
- **Notifications, not nagging.** Due‑date reminders and an optional payday plan
  summary; local notifications work with the app closed.

---

## 8. Accessibility

- **VoiceOver:** interactive elements have labels; composite rows use
  `accessibilityElement(children:.combine/.ignore)`; charts expose a summary
  rather than unlabeled marks (e.g. "Received …, spent …, net loss …").
- **Contrast (WCAG 2.1):** white on the light hero gradient ≥ 4.5:1;
  `brandPrimary` on white ≈ 5.8:1; `moneyIn`/`moneyOut` ≥ 4.5:1 in both modes.
- **Color never alone** — always paired with glyph/text.
- **Dynamic Type** via text styles and `ViewThatFits`‑style reflow (no
  `GeometryReader` hacks).

---

## 9. Localization

- Fully localized **English, Korean (ko), Nepali (ne)** across two String
  Catalogs: the App (`App/Localizable.xcstrings`) and the package
  (`KharchaKit/.../Resources/Localizable.xcstrings`, `defaultLocalization: "en"`).
- Currency is locale/selection‑aware; pasted foreign amounts convert to the base
  currency automatically.
- Terminology glossary is kept consistent across screens (e.g. commitments =
  고정 지출 / नियमित खर्च; savings = 저축 / बचत).

---

## 10. Data‑integrity as a design constraint

- **Engine does the math; AI does the words.** `ExpenseTextExtractor` /
  `PlanAdvisor` fall back to deterministic parsing/templates when Apple
  Intelligence is unavailable.
- **Local‑first with newest‑wins sync.** SwiftData on device; Firestore per‑user
  (`/users/{uid}/…`) with `updatedAt` conflict resolution + tombstones. Adding
  features is additive (no destructive migrations).

---

## 11. Feature map

Home · History/Activity (charts + calendar) · Monthly Plan (forecast, target
income, pre‑alerts) · Budgets · Savings (pots + goals + envelope allocation) ·
**Installments & Loans** (finite obligations with a payment ledger) · Reminders
(recurring rules) · Friends/Debts · Import‑from‑text (Apple Intelligence) ·
Settings (currency, language, backup/sync, CSV export) · Siri App Intents.

---

## 12. Known gaps / roadmap (honest)

Measured against Rams/Norman, the current build is "clean HIG" but not yet
best‑in‑class. Open work:
- **Onboarding & empty states** — no first‑run story; empty screens are plain.
- **Distinctiveness & delight** — visuals are tasteful but generic; little motion.
- **Real usability testing** — verified function on device, not comprehension with
  users.
- **Charts depth** — no trend comparisons vs. previous period, no category drill‑in
  from the bar chart yet.
- **IA at scale** — if More keeps growing, promote a dedicated "Plan" hub tab.

---

## Sources

- [HIG — Color](https://developer.apple.com/design/human-interface-guidelines/foundations/color/) ·
  [HIG — Branding](https://developer.apple.com/design/human-interface-guidelines/branding)
- Dieter Rams — *Ten Principles of Good Design* (Braun / Vitsœ)
- Don Norman — *The Design of Everyday Things*
- [Fintech UI/UX best practices](https://www.theskinsfactory.com/uiux-design-blog/fintech-ui-ux-design) ·
  [Fintech color palettes](https://www.inspoai.io/blog/best-color-palette-for-fintech-app)

> A fuller, sourced research report (top designers' principles, fintech patterns
> from Monzo/Revolut/Copilot/YNAB, and a scored Kharcha critique) is generated
> separately via the deep‑research pass — see `docs/design-research.md` when added.
