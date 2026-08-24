# myKharcha Product Principles

These principles govern every product decision — what goes on Home, what qualifies as a Quick Action, when to show a card inline vs. behind a tap, and what belongs in More. They are grounded in well-validated design research and tuned to personal finance apps.

---

## Frameworks We Follow

### 1. Jobs-to-Be-Done (Clayton Christensen)
Users don't "use a finance app." They hire it to do specific jobs at specific moments:

| Job | Moment | Design implication |
|-----|--------|--------------------|
| **"Am I on track this month?"** | Morning glance | Balance hero + MonthGlanceCard must answer this in < 2 seconds |
| **"Log what I just spent"** | Right after a purchase | Add is always the first quick action, never buried |
| **"Did I overspend my budget?"** | End of week | Budget health visible inline — no tap required |
| **"Is my payment due soon?"** | Week before payday | Due-soon strip on Home, not just in Installments |
| **"Where did my money go?"** | Month review | History + donut chart — behind a tab, not on Home |

> Rule: A Home section earns its spot only when it serves a daily job. Monthly-review jobs belong in History.

---

### 2. Fogg Behavior Model — B = MAP (BJ Fogg)
Behavior happens when **Motivation**, **Ability**, and **Prompt** converge at the same moment.

- **Motivation** is highest right after a purchase (regret/intent) or right before payday (urgency).
- **Ability** requires the path to be one tap. Every additional tap halves conversion.
- **Prompt** must be contextual: "Nothing logged today — add one?" is a prompt timed to the right moment; a permanent "Log expense" banner is noise.

> Rule: Quick Actions must take ≤ 1 tap to trigger the primary action. The number of tiles on Home is capped at 4 — beyond that, ability drops.

---

### 3. Progressive Disclosure (Nielsen Norman Group)
Show the information users need for the current task; reveal detail only on demand.

- **Level 0 (Home):** Balance, quick actions, budget health, due-soon. Enough to answer "am I OK?"
- **Level 1 (tap into a section):** Budget bars, spending donut, pay cycle detail.
- **Level 2 (tab or More):** Full history, savings pots, installment ledger, reminders, settings.

> Rule: Never promote a feature to Level 0 because it exists. Promote it only when users check it daily without prompting.

---

### 4. Feedback Loop (Don Norman — The Design of Everyday Things)
Every action needs immediate, unambiguous feedback. The loop: **Gulf of Execution → Action → Gulf of Evaluation → Feedback**.

Applied to myKharcha:
- Logging an expense: the balance hero must update on next load (within 1 refresh cycle).
- Signing in for backup: the Back up tile becomes "Synced" (green checkmark) immediately after authentication.
- Recording an installment payment: remaining balance and progress bar update immediately in the detail screen.
- Deleting a transaction: it disappears from Recent instantly (optimistic UI).

> Rule: Never require the user to navigate away and back to see the result of their action.

---

### 5. Make Users Feel Competent (Kathy Sierra — *Badass: Making Users Awesome*)
The goal is not for users to be good at the app — it's for users to be good at managing their money. The app succeeds when users feel financially in-control, not when they master the feature list.

- Show momentum: "All 3 budgets on track" is more motivating than showing a list of three green bars.
- Avoid shame language: "Nothing logged today — add one?" is an invitation, not a guilt trip.
- Surface wins: net-positive weeks should read green and feel like a reward.
- Keep the UI sparse: a cluttered Home makes users feel behind, not in control.

> Rule: Every new Home section must make the user feel more in control, not more overwhelmed.

---

## Home Screen Decision Framework

### What Qualifies as a Quick Action

A tile earns a Quick Action spot if **all three** are true:
1. **Daily frequency** — the action is done at least a few times per week by an active user.
2. **One tap to start** — tapping the tile immediately begins the action (no intermediate screen required to get value).
3. **No screen-state required** — the user doesn't need to see prior data before triggering it.

| Tile | Qualifies? | Reason |
|------|-----------|--------|
| Add | ✅ | Logged daily; opens form immediately |
| Import | ✅ | Weekly; opens scanner immediately |
| Plan | ✅ | Weekly check-in; opens plan immediately |
| Back up / Synced | ✅ | Persistent state indicator; one-tap CTA until done |
| Budgets | ❌ | Passive monitoring (show inline as MonthGlanceCard instead) |
| Savings | ❌ | Monthly task; belongs in More |
| Installments | ❌ | Monthly task; due-soon shown inline instead |
| Reminders | ❌ | Configuration task; belongs in More |

### Home Information Architecture (top to bottom)

```
Balance hero          ← answers "how am I doing this month?"
Quick actions (4)     ← enables the most common daily actions
Month at a glance     ← answers "am I on track?" without a tap
This Week chart       ← shows trend without navigation
Pay cycle card        ← answers "how much can I spend today?"
This Month donut      ← shows where money went (discovery)
Budget bars           ← shows per-category progress
Friends strip         ← surfaces unsettled balances
Recent (grouped)      ← lets user verify today's logging
```

### Inline vs. Navigate

| Show inline (Level 0) | Navigate required (Level 1+) |
|----------------------|------------------------------|
| Budget health summary (N on track) | Full budget bars with editing |
| Due-soon installment name + amount | Installment detail + payment ledger |
| Pay cycle: days left + safe-to-spend | Pay cycle configuration |
| This week's trend bars | Full history with filters |
| Recent (last 10, grouped by day) | Full transaction history |

---

## Content Priority Rules

1. **Negative states surface first.** Overspent budget or overdue payment appears at the top of `MonthGlanceCard` before positive states.
2. **Empty sections are hidden.** Never show a section header with nothing inside it. Sections with no data simply don't render.
3. **Conditional > Always.** If a section serves fewer than ~50% of active users on any given day, it's conditional (only visible when relevant).
4. **Recency beats comprehensiveness in Recent.** 10 rows, most recent first, grouped by day. The user does not need a full ledger on Home.
5. **Status tiles beat banners.** The Back up tile is a persistent state machine (one of 4 tiles) — not a dismissible banner that competes with the balance hero.

---

## Scope Guardrails

These are decisions we have already made and should not revisit without strong user evidence:

- **4 quick action tiles, no more.** Adding a 5th demotes the others and increases cognitive load.
- **No horizontal scroll on Home quick actions.** Hidden items = lower discoverability. All 4 tiles must be visible at once.
- **MonthGlanceCard never requires a tap.** If answering the question requires a tap, it belongs in a tab, not the card.
- **No duplicate entry points.** Installments appear in More → Plan. Due-soon appears inline. Not both as navigation links on Home.
- **Engine does all math.** Apple Intelligence / on-device model reads and writes text only. Arithmetic (balances, percentages, remainders) is always computed in KharchaKit — never inferred from a language model.
