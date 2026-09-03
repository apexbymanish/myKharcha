# Kharcha — Design Research & Rams Scorecard

Cited research backing `DESIGN.md`. Produced by a deep-research pass (16 sources →
49 candidate claims → 25 adversarially verified, 12 confirmed). **Honesty note:**
the primary-source design/accessibility claims below were each verified by a 3-vote
adversarial check (shown as `3-0`/`2-1`). The fintech-blog claims in §3 could **not**
be independently verified in this run (the verifier agents hit API rate limits and
abstained), so they're presented as *industry guidance, not confirmed fact*, and
come from blog-tier sources.

---

## 1. Design principles (verified, primary sources)

### Dieter Rams — Ten Principles of Good Design  ✅ 3-0
Good design is: (1) innovative, (2) makes a product useful, (3) aesthetic,
(4) understandable, (5) unobtrusive, (6) honest, (7) long-lasting, (8) thorough
down to the last detail, (9) environmentally-friendly, (10) **as little design as
possible** — *"Less, but better – because it concentrates on the essential
aspects."*
Sources: [Vitsœ (primary)](https://www.vitsoe.com/us/about/good-design) ·
[Design Museum](https://designmuseum.org/discover-design/all-stories/what-is-good-design-a-quick-look-at-dieter-rams-ten-principles)

- **"Honest"** = design *"does not make a product more innovative, powerful or
  valuable than it really is."* ✅ 3-0 — this is the principle Kharcha leans on
  hardest (see §4).

### Don Norman — The Design of Everyday Things  ✅ 3-0
- The two most important characteristics of good design are **discoverability** and
  **understanding**. ✅ 3-0
- Discoverability comes from five concepts — **affordances, signifiers,
  constraints, mappings, feedback** — plus a sixth, the **conceptual model**, which
  "provides true understanding." ✅ 3-0
- **Affordances** determine what actions are possible; **signifiers** communicate
  where the action takes place — "we need both." ✅ 2-1
Source: [Norman, *DOET* (primary PDF)](https://media.aanda.psu.edu/sites/media/aa/files/documents/norman_design-of-everyday-things.pdf)

### Jony Ive
No claim survived verification (the two Ive sources were rated unreliable and
yielded 0 usable quotes). Treat his contribution as *well-known but unsourced here*
— simplicity as "bringing order to complexity," Rams-influenced restraint.

---

## 2. Apple HIG & iOS accessibility (verified, primary sources)

- **Contrast:** an app can claim "Sufficient Contrast" when common-task UI (text,
  buttons, controls) meets general guidance *"usually 4.5:1 for most text"*, with
  **3:1 for non-text** elements (controls, state indicators). ✅ 3-0
  *(A stricter "4.5:1 is a hard requirement for all foreground text" framing was
  refuted 1-2 — the real guidance is "usually 4.5:1", not absolute.)*
  Source: [App Store Connect — Sufficient Contrast criteria (primary)](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/sufficient-contrast-evaluation-criteria/)
- **Typography:** iOS default text size **17 pt**, minimum **11 pt** (both custom &
  system fonts). ✅ 3-0
- **Dynamic Type:** using system **text styles** with system fonts automatically
  supports Dynamic Type and the larger accessibility sizes. ✅ 3-0
- **Layouts must adapt** and stay legible at *all* Dynamic Type sizes — verify via
  Settings → Accessibility → Display & Text Size → Larger Text. ✅ 3-0
Source: [HIG — Typography (primary)](https://developer.apple.com/design/human-interface-guidelines/typography)

---

## 3. Fintech/budgeting UX patterns (unverified — blog-tier, use as guidance)

⚠️ Not independently verified in this run (verifier abstained under load). Directional only:
- Finance onboarding should **explain value before requesting account access**, and
  break setup into sequential steps (progressive disclosure), as Revolut/Nubank/
  Monzo do — with plain-language microcopy. [appthetics] · [craftinnovations]
- Dashboards should **answer the user's core questions instantly** (total spend,
  remaining budget, urgent items) with clear labels, grouped categories, consistent
  icons, generous spacing. [onething.design]
- **One-tap expense entry** and a scannable UI matter for retention. [onething.design]
- Chart fit: **progress bars** for a category's limit, **line charts** for cash-flow
  over time, **stacked bars** for comparing categories across periods; **pie charts
  degrade** with many categories. [appthetics]
- Copilot Money is often cited as the most visually polished iOS budgeting app.
  [envelopebudgeting] *(opinion, single blog source)*

---

## 4. Kharcha scored against Rams' Ten Principles

My assessment (grounded in the verified principles above + the current codebase).
Scores are a self-audit, not third-party.

| # | Principle | Score | Evidence / gap |
|---|-----------|:---:|----------------|
| 6 | **Honest** | 5/5 | Engine computes every number; AI only reads/writes text; forecasts never double-count actuals. This is the app's strongest axis and directly embodies Rams #6. |
| 2 | **Useful** | 4/5 | Covers logging, budgets, savings, installments/loans, plan, debts, import. |
| 4 | **Understandable** | 4/5 | Amount-first entry, **Net indicator** with arrow, More rows with subtitles, kind-filtered categories. Gap: no onboarding/conceptual-model intro (Norman's "sixth principle"). |
| 5 | **Unobtrusive** | 4/5 | Progressive disclosure for installments; don't-force-login; don't-nag. |
| 10 | **As little design as possible** | 4/5 | Single accent, system neutrals, no gratuitous chrome. |
| 7 | **Long-lasting** | 4/5 | Local-first, additive migrations, newest-wins sync. |
| 8 | **Thorough to the last detail** | 3.5/5 | Strong: ko/ne localization, VoiceOver, WCAG contrast, 228 tests. Gaps: empty states are plain; **Dynamic-Type audit at the largest accessibility sizes not yet done** (verified HIG requirement). |
| 1 | **Innovative** | 3/5 | On-device AI text import + installment tracking are nice; overall a familiar category. |
| 3 | **Aesthetic** | 3/5 | Clean and HIG-correct, but generic — no distinctive visual voice or motion. |
| 9 | **Environmentally-friendly** → *efficient/sustainable* | 3/5 | (N/A for software; read as resource-frugal.) Local-first, minimal network. |

---

## 5. Prioritized redesign roadmap (highest impact first)

1. **First-run onboarding + real empty states.** Biggest gap vs Norman's
   conceptual-model principle and fintech onboarding guidance — state the value,
   one setup input (currency/salary), preview with sample data. *(Understandable, Thorough)*
2. **Dynamic-Type pass at largest accessibility sizes.** Verified HIG requirement;
   confirm no truncation on Add/Home/History at max size. *(Thorough — concrete, testable)*
3. **Chart depth in History/Activity.** Add previous-period comparison and
   category drill-in from the bar chart; keep pie/donut category-count low. *(Useful, Understandable)*
4. **A distinctive but restrained visual voice.** Typography scale, iconography,
   subtle motion on the balance hero and chart transitions — without violating
   "as little design as possible." *(Aesthetic)*
5. **Usability testing with real users** (comprehension, not just function) — the
   one thing no amount of self-audit can replace.

---

## Sources (quality-rated by the research pass)

Primary: Vitsœ · Norman *DOET* PDF · Apple HIG Typography · Apple Sufficient-Contrast
criteria · Apple HIG Color. Secondary: Design Museum · NN/g. Blog (directional):
appthetics · craftinnovations · onething.design · envelopebudgeting. Rated
unreliable/skipped: two Jony Ive articles, a banking-patterns Medium post, some HIG
sub-pages that returned no extractable quotes.
