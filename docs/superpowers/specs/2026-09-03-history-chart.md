# History chart — where it landed

**Date:** 2026-09-03
**Branch:** `feat/app-shell`
**Range:** `cd02bae..3c84847`

A record of what the History screen became over one session, why each
decision was made, and which of them were corrections of my own mistakes.
Written after the fact — this is not a plan, and the two plan documents
this session produced are dead (see *Abandoned*).

---

## What History is now

One screen, one job: a full-height bar chart you scroll horizontally, with
a hero figure above it. Modelled on Pedometer++.

```
┌──────────────────────────────┐
│ History                   ◕  │  ← Reports lives behind the toolbar button
│                              │
│         ₩1,896,520           │  ← spent, the figure that dominates
│      ₩3,000,000 received     │  ← qualifiers, always laid out
│       ↑ ₩1,103,480 net       │
│                              │
│    ▏  ▎     ▁                │
│    █  █  ▁  █   ▁            │  ← spend, split by category, off the bottom
│ ───────────────────────────  │  ← zero rule at ¾ height
│         ▓                    │  ← income, own scale, lower quarter
│ Sep 1   Sep 3   Sep 5        │
└──────────────────────────────┘
```

Everything else — search, the All/Expenses/Income segment, Filters, the
W/M/Y scope control, the transaction ledger — left. Most of it is in
Reports now; the rest is listed under *Outstanding*.

---

## The decisions, and what forced them

### Free scroll, not paged

An earlier instruction was per-unit paging: pick Month and the chart pages
one month at a time. That was built (`6e44f7d`) and then reversed. Paging
makes the boundary between two periods a wall — spending on the 31st and
the 1st are one week of your life, and paging refuses to show them
together. Pedometer++ scrolls freely and so does this now. Roughly nine
buckets are visible at a time, which is the ceiling for keeping an amount
legible on every bar.

### Every bar carries its amount

No scrubbing, no tap-to-reveal. A value you have to uncover is a value most
people never see. The tooltip still exists for a tapped bar, but it is not
how you read the chart.

### Bars split by category, largest band named inside itself

The fill used to encode budget status — green under allowance, red over. A
fill can encode one thing, and *what the money went on* beats *whether the
day beat its allowance*, which the hero and Reports already say. Bands take
the colours their categories already wear elsewhere in the app, so the
colour reads twice.

Anything under **8.3%** of a day merges into "Other" rather than drawing a
band too thin to see. A band deeper than **22%** of the ceiling carries its
category name in dark ink; below that it is a colour stripe and the legend
carries the meaning.

### Income diverges below a zero rule, on its own scale

Income was originally pulled from the chart entirely, because one salary is
twenty times a day's spending and on a shared axis it flattens every
expense bar to nothing. It came back split: spending above the rule,
income below, scaled independently into the lower quarter.

**The cost is real and worth stating:** heights are not comparable across
the zero line. A green bar twice a red one does not mean twice the money.
The rule and the colour split are what tell the reader these are two
different measures.

### Scaling derives from the visible window

Not from the series. Three separate things follow from this:

| Quantity | Rule |
|---|---|
| Ceiling | 90th percentile of visible spend, ×1.1 headroom; falls back to max under 4 buckets |
| Bar width | 0.98 → 0.72 of the column as the window fills up |
| Zero rule | Fixed at ¾ height whenever anything was received |

The percentile ceiling means one rent-sized day clips instead of flattening
the month. The width ramp exists because two bars in a nine-column grid at
a fixed ratio look lost — and varying the ratio is deliberate, because
pushing `chartXVisibleDomain` low enough to fatten bars makes Swift Charts
stop honouring bar width at all.

### Empty days keep their column

A grey stub on the baseline, 1.8% of the height. A no-spend day is visibly
a day, not a gap in the data.

### The empty state is an overlay

It used to *replace* the chart. That removed the only way to scroll back to
a period that had data — the user was stranded on a screen with no exit. It
now sits over the chart with `allowsHitTesting(false)`, so the scroll
underneath still works, and says "Swipe to another period".

---

## Bugs found, and what actually caused them

The session opened with a real bug and closed with three of my own. All
four are the same shape: **two things that must agree, computed from
different sources.**

### The chart always described today

The reported bug. `now: Date()` was passed at render, so the headline said
"August" while the bars showed whatever you had scrolled to. Three separate
month states existed across the view and view model. Collapsed to one
anchor owned by the view model, so the scroll position, the summary and the
bars cannot disagree.

### The scroll anchor fed back into its own domain

Caught by a test: a 31-bar series became **2,404 bars**. The anchor moved
the window, the window extended the series, the longer series moved the
anchor. Fixed by splitting `recomputeSeries` (uses a `seriesNow` captured
once per load) from `recomputeSummary` (uses the live anchor).

### `Decimal / 0` returns NaN silently

No trap, no crash — just a percentage that renders as garbage. `changeRatio`
returns `Decimal?` now.

### Week start inherited the device locale

Weeks silently began on Monday for some users and Sunday for others, so two
people comparing the same week saw different bars. `sundayFirst` pins
`firstWeekday = 1`; the test sets `firstWeekday = 2` deliberately to prove
the pin holds.

### Labels were suppressed on every bar

`labelsFit` tested `bars.count` — the whole scrollable series, up to 800
buckets — rather than the handful on screen. It was therefore always false,
and every amount and category name was silently dropped. The visible window
is fixed at nine buckets by `visibleDomain`, so labels always fit.

### The ceiling was computed over the whole series

A window holding one ₩11,180 day was measured against a ceiling drawn from
months of history. The bar rendered correctly — at 1.6% of a height it had
no business being compared to.

### The income floor was measured in the wrong unit — *mine*

The worst of them, and a reintroduction of the exact problem the income
split was built to solve. `floorValue` derived the bottom of the y-axis
from `incomePeak`, a money amount, rather than from the other end of the
axis it was defining:

```
₩3,000,000 received, ₩130,000 spent
  →  domain -9,000,000 … 130,000
  →  the entire expense half drawn in the top 1.4% of the plot
```

Hairline bars with their amount labels piled on a single line. It now
derives from `spendTop`, so the zero rule sits at three-quarters height
regardless of what was received.

### A no-spend window had no scale — *mine*

With `peak` at zero, the grey stubs were drawn `0 × 0.012` tall and
vanished, and the domain topped out at a hardcoded `1`. A run of no-spend
days read as a broken chart. `spendTop` floors the domain at 1.

### The income label collided with the date axis — *mine*

`position: .bottom` hung the figure off the far end of the bar, so the
taller the income the lower the label went. At full height it landed on the
axis. Now `position: .overlay, alignment: .top`, inside the bar under the
zero rule, so it holds one position at any height.

### The hero collapsed mid-scroll — *mine*

"received" and "net" sat behind `if s.income > 0`. Scrolling from a month
with a salary to one without removed two lines outright, shrinking the hero
and yanking the chart up under it. They hold their space and cross-fade
now.

---

## Localization

The headline was briefly built by concatenation:

```swift
Text(" is ") + Text("down 8%") + Text(",")   // never do this
```

`" is "` is not a translatable key, and the fixed word order breaks outright
in Arabic and Urdu — both of which this app ships. It is four whole
sentences now, one per trend case, with `DateIntervalFormatter` for week
ranges so the locale picks its own separator and collapses repeated parts
("Aug 17 – 23", not "Aug 17 – Aug 23").

**The new keys have zero translations across all 20 languages.** They fall
back to English everywhere.

---

## Type-checker limits

`ActivityCharts.swift` hit *"unable to type-check this expression in
reasonable time"* twice.

- The `Chart` body, carrying income marks, the zero rule, empty stubs,
  stacked category bars and two annotations each — split into five
  `@ChartContentBuilder` properties.
- Earlier, `HistoryView`'s `List` body — split into `transactionSection`.

Related and worth knowing: **a `let` binding inside a `ChartContentBuilder`
closure defeats its inference**, and the failure surfaces as a completely
misleading *"cannot convert `[ActivityBar]` to `Binding<C>`"*. Precompute
into a property instead.

Two APIs I invented and had to correct: `.chartClipShape(_:)` does not
exist, and the overflow strategy is `.fit(to: .chart)`, not `.fitToChart`.
Both produced misleading cascade errors several lines away.

---

## Abandoned

**Pinch-to-zoom** — replacing W/M/Y with a three-rung pinch (week → month →
year), scrolling ±5 years. Fully specced, planned, and partly implemented
across four commits before being dropped: *"any thing deos not work, forget
about pnich, can yiu make scrollabel"*. The two documents remain in the
repo and should be read as history, not intent:

- `docs/superpowers/specs/2026-09-03-chart-pinch-zoom-design.md`
- `docs/superpowers/plans/2026-09-03-chart-pinch-zoom.md`

---

## Outstanding

| Item | Note |
|---|---|
| W/M/Y has no home | Removed from History, never added to Reports. Chart scope is pinned to `.month`. |
| Reports has no row preview | The four-row + "Show all N" pattern died with History's list. |
| `SectionHeader` is orphaned | Still in `HistoryView.swift`, no caller. |
| New strings untranslated | 0 of 20 languages. |
| Adjacent label collision | Two tall neighbouring bars can still overlap their amounts horizontally. `minimumScaleFactor(0.75)` absorbs some, not arbitrary width. Needs a dense week to judge. |
| `HomeViewModelTests.swift:23` red | `recent.count → 5` vs `== 10`. **Predates this session — assertion untouched pending your check.** |
| Five duplicate Stitch screens | `da9768ea`, `d6ebe6cf`, `2e42cff3`, `0a269a4d`, `4835a3d3` — delete manually. |

---

## Build and test

Xcode holds a lock on the shared build folder, so builds go to a scratch
tree:

```bash
SCRATCH=/private/tmp/claude-501/.../scratchpad/xcbuild
xcodebuild -scheme Kharcha \
  -destination 'generic/platform=iOS Simulator' \
  OBJROOT=$SCRATCH/obj SYMROOT=$SCRATCH/sym build
```

```bash
cd KharchaKit && swift test    # 267 / 268 — the one red is the pre-existing HomeViewModel case
```

---

## Commits

| | |
|---|---|
| `2ffb6f1` `4f9b296` | pinch-to-zoom spec and plan — **abandoned** |
| `a08129a` | chart follows the period you are looking at |
| `c1969de` `db21372` | pinch scale rungs — **abandoned** |
| `6dd2abc` | cap the continuous series so long ledgers stay bounded |
| `1410783` | a summary can report an empty visible range |
| `6e44f7d` | scroll by the unit the scope names — **reversed** |
| `521ad59` | make the chart headline translatable |
| `225507d` | preview four rows per month — **superseded** |
| `1e5de95` `1ba45e2` | strip History to the graph; ledger moves to Reports |
| `5f2f16b` | scale to the 90th percentile, not the outlier |
| `70b9e3f` | category-stacked bars with diverging income |
| `cc4d5ae` | anchor the income amount; keep a scale when nothing was spent |
| `3c84847` | scale the income floor against spending; stop the hero collapsing |
