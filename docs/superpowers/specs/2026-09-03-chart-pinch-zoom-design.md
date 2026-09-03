# History chart: pinch to zoom

*2026-09-03*

## Problem

The History chart's scope is set by a `[W | M | Y]` segmented control in the
analytics card header. Three fat segments compete with the chart for the header
row, and the control is the noisiest element on a screen whose whole point is the
chart. Replacing it with a pinch gesture removes the chrome and makes changing
scope feel continuous rather than like flipping a switch.

## Goals

- Pinch to change chart scope; no permanent scope control on screen.
- Zoom tracks the fingers smoothly — no stiffness, no mid-gesture flicker.
- Scope is legible when it changes, invisible when it isn't.
- Every capability reachable without the gesture.
- Scrolling reaches ±5 years; empty stretches say so rather than looking broken.

## Non-goals

- Zooming below a day or above a year. A bar is never an hour or a decade.
- Pinch-to-zoom anywhere else in the app.
- Changing how bars are coloured, labelled by value, or how the list follows the
  chart. Those are settled and out of scope here.

## The zoom ladder

Three rungs. Each rung shows one whole period.

| Rung | Bar is | Visible span | Bars on screen |
|---|---|---|---|
| In | a day | one week | 7 |
| Mid | a day | one month | 28–31 |
| Out | a month | one year | 12 |

`ActivityPeriod` (`.week` / `.month` / `.year`) already models exactly this and
survives unchanged. The rung *is* the period. This keeps the model layer almost
untouched — `bars`, `continuousBars`, `summary` and `allowancePerBucket` all keep
their current signatures.

A fourth "several years" rung was considered and rejected: it needs a year-bucket
type the model does not have, and ten mostly-empty bars is a worse answer than
scrolling.

## Gesture model

**Continuous scale during the pinch, snap and re-bucket on release.**

Bar granularity is discrete — 31 day-bars cannot smoothly become 12 month-bars.
So the pinch does *not* re-bucket live. It scales the visible domain only: bars
keep their current granularity and get proportionally thinner or fatter, tracking
the fingers exactly. On release, the scale snaps to the nearest rung and the
buckets change once, animated.

The rejected alternative was re-bucketing live at scale thresholds. It pops under
the fingers and flickers near a boundary unless damped with hysteresis. Smooth
tracking plus one clean transition beats continuous correctness here — it is what
Photos does when you pinch the grid.

Accepted cost: mid-gesture you can briefly see 31 very thin day-bars before they
resolve into 12 month-bars on release.

### Where the gesture lives

On the **analytics card**, not the chart. The chart is ~200pt tall — a poor target
for two fingers — and it already owns a horizontal scroll view whose recogniser
the pinch would have to fight. The card is a larger, quieter target.

### Gesture arbitration

Four recognisers overlap in this area:

| Gesture | Owner | Arbitration |
|---|---|---|
| Vertical drag | enclosing `List` | one finger, vertical |
| Horizontal drag | chart's scroll view | one finger, horizontal |
| Pinch | analytics card | **two fingers** — disjoint from the drags |
| Tap | chart (`chartXSelection`) | no movement |

Finger count separates pinch from both drags, which is the reason this is
tractable at all. The risk is not ambiguity but *swallowing*: the `List` and the
chart's scroll view may claim the touches before the card's recogniser sees them.
Mitigation is `simultaneousGesture` on the card; if that proves insufficient the
fallback is a `UIViewRepresentable` wrapper owning a `UIPinchGestureRecognizer`
with an explicit failure relationship.

**This is the single largest implementation risk in the plan** and should be
spiked before the rest is built.

## Transient scope indicator

No permanent control. During the pinch a label fades in over the chart —
`Week` / `Month` / `Year` — and fades out ~1s after the fingers lift. Same
pattern as the system volume HUD or the Maps zoom readout: state is shown while
state is changing, and nothing the rest of the time.

Rendered as an overlay on the plot area, not in the header row, so it does not
reintroduce the layout cost the segmented control had.

## Empty-range overlay

Scrolling reaches ±5 years, so most of that range is empty for a new user. Empty
today reads as broken: no bars, possibly a row of grey no-spend dots, possibly
nothing at all, with no explanation.

When the visible window contains no transactions, overlay the plot area with
`No transactions in <period>` — "in May 2026", "in 2021". This replaces the
emptiness rather than leaving the user to interpret it.

Distinct from the existing no-spend dot, which marks a day that exists and had
zero spending. The overlay marks a *range* with nothing in it at all.

## Accessibility

Pinch cannot be the only route to scope. VoiceOver, Switch Control and Voice
Control users cannot perform it, and the HIG treats gesture-as-sole-route as a
defect.

`.accessibilityAdjustableAction` on the chart maps VoiceOver's swipe up/down to
the zoom rungs and announces the new scope. Invisible to sighted users, no layout
cost, and it is the difference between this passing review and not.

## Consequences to accept

**Label density stops being uniform.** The current rule is "every bar carries its
amount", which works because ~9 bars are visible. At the Mid rung a whole month is
28–31 bars and the labels cannot all fit. Labels therefore become rung-dependent:
all bars at In (7) and Out (12), thinned at Mid. This partially unwinds an earlier
decision and should be a conscious trade, not a surprise.

**±5 years of daily buckets is expensive.** `continuousBars` currently generates
one bar per day across the whole domain. Ten years is ~3,650 `ActivityBar`s
rebuilt on every reload. The domain must be generated lazily around the anchor
rather than spanning the full range eagerly.

## Model changes

Small, because `ActivityPeriod` carries the rungs.

- `HistoryViewModel.State` gains `zoomScale: Double` — the live pinch scale,
  1.0 at rest. Drives `chartXVisibleDomain` during the gesture only.
- `HistoryViewModel.setZoomScale(_:)` — continuous, view-only, no reload.
- `HistoryViewModel.settleZoom()` — snaps to the nearest rung, sets
  `chartPeriod`, recomputes.
- `ActivitySeries.continuousBars` gains a bounded window so it does not build a
  decade of daily buckets.
- `ActivityBarChart` loses its `period` picker binding; gains `zoomScale`.
- The `Picker` in `analyticsSection` is deleted.

## Testing

Model layer, TDD as usual:

- Snapping picks the nearest rung from a given scale, including at the midpoints.
- Snapping is stable — settling twice at the same scale does not change rung.
- Zoom preserves the anchor: zooming at August stays in August.
- `continuousBars` respects its window bound and does not grow with the ±5 year
  domain.
- Empty-range detection is true only when the window genuinely holds no rows.

Not unit-testable, must be checked on device: gesture arbitration against the two
scroll views, whether mid-gesture thin bars read as broken, indicator timing, and
whether losing per-bar labels at the Mid rung is acceptable.

## Open question

Whether the domain should span a full ±5 years regardless of data, or clamp to
the data range plus a margin. Spanning the full range means a new user can scroll
through nine years of "No transactions" overlays. Clamping means the range grows
as they use the app. Leaning clamp-plus-margin; not settled.
