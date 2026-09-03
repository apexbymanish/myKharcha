# History Chart Pinch-to-Zoom Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the History chart's `[W | M | Y]` segmented control with a pinch gesture that zooms through three rungs, with a transient scope indicator and an empty-range message.

**Architecture:** `ActivityPeriod` already models the three rungs, so the model layer barely changes. A live `zoomScale` scales the chart's visible domain during the pinch without re-bucketing; on release it snaps to the nearest rung and re-buckets once. The gesture attaches to the analytics card, not the chart, to stay clear of the chart's own horizontal scroll view.

**Tech Stack:** Swift 6, SwiftUI, Swift Charts, Swift Testing (`@Test`/`#expect`), SwiftData. iOS 26 deployment target.

**Spec:** `docs/superpowers/specs/2026-09-03-chart-pinch-zoom-design.md`

## Global Constraints

- Deployment target is iOS 26 (`IPHONEOS_DEPLOYMENT_TARGET = 26.0`, `Package.swift` `platforms: [.iOS(.v26)]`). Every Swift Charts and SwiftUI API from iOS 17-26 is available.
- Model code lives in `KharchaKit/Sources/KharchaKit/`; view code in `App/Views/`. Never put presentation in `KharchaKit`.
- Tests use Swift Testing: `@Test func name() { #expect(...) }`. Not XCTest.
- Test helpers `testCal` (Gregorian, `Asia/Seoul`, `firstWeekday = 2`) and `d(y,m,day,h=12)` are in `KharchaKitTests/TestSupport.swift`. Reuse them; do not redefine.
- `testCal.firstWeekday == 2` (Monday) deliberately, to prove production pins Sunday. Never change it.
- Run model tests from the `KharchaKit` directory: `swift test`.
- Xcode holds a lock on the shared build folder. Build the app with relocated paths:
  `xcodebuild -scheme Kharcha -destination 'generic/platform=iOS Simulator' OBJROOT=/tmp/kzoom/obj SYMROOT=/tmp/kzoom/sym build`
- `HomeViewModelTests.loadPopulatesMonthTotalsAndRecent` is RED before this work starts (expects `recent.count == 10`, production returns `prefix(5)`). It is out of scope. A run showing exactly this one failure is green for our purposes.
- Money is `Decimal`. Never `Double` for amounts.

---

### Task 1: Spike — can the card own a pinch gesture?

This is a **spike**, not production code. The spec names gesture arbitration as
the single largest risk: the enclosing `List` and the chart's horizontal scroll
view may swallow touches before the card's recogniser sees them. Find out before
building anything on top of it.

**Files:**
- Modify: `App/Views/HistoryView.swift` (temporary; reverted at the end of this task)

**Interfaces:**
- Consumes: nothing.
- Produces: a yes/no answer recorded in the plan, plus the chosen mechanism
  (`simultaneousGesture` vs `UIViewRepresentable`). No API.

- [ ] **Step 1: Add a throwaway pinch probe to the analytics card**

In `HistoryView.swift`, find `analyticsSection`. Attach a probe to the
`DisclosureGroup`'s content — the whole card area:

```swift
.simultaneousGesture(
    MagnificationGesture()
        .onChanged { scale in print("[ZOOM PROBE] changed \(scale)") }
        .onEnded { scale in print("[ZOOM PROBE] ended \(scale)") }
)
```

- [ ] **Step 2: Build and run on a device or simulator**

Run:
```bash
xcodebuild -scheme Kharcha -destination 'generic/platform=iOS Simulator' \
  OBJROOT=/tmp/kzoom/obj SYMROOT=/tmp/kzoom/sym build
```
Then launch and open History. On a simulator, pinch with Option+drag.

- [ ] **Step 3: Record what happens**

Check all four in the console and by feel:
1. Does `[ZOOM PROBE] changed` fire at all when pinching over the chart?
2. Does it still fire when pinching over the card but *not* over the chart?
3. Does one-finger vertical drag still scroll the `List` normally?
4. Does one-finger horizontal drag still scroll the chart normally?

- [ ] **Step 4: Decide the mechanism**

If 1-4 all pass, `simultaneousGesture` is sufficient — record that and continue.

If (1) fails — the chart's scroll view swallows the pinch — the fallback is a
`UIViewRepresentable` hosting a `UIPinchGestureRecognizer` whose delegate returns
`true` from `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)`, placed as a
transparent overlay on the card. Record that this is needed; Task 6 will use it.

If (3) or (4) break, stop and report. That means the gesture cannot coexist with
the scroll views, and the feature needs redesign rather than implementation.

- [ ] **Step 5: Revert the probe and record the finding**

```bash
git checkout App/Views/HistoryView.swift
```

Append the finding to the plan file under this task, then:

```bash
git add docs/superpowers/plans/2026-09-03-chart-pinch-zoom.md
git commit -m "docs: record pinch gesture spike findings"
```

---

### Task 2: Snap a continuous scale to the nearest rung

Pure model logic. The pinch produces a continuous scale; this converts it to a
rung on release.

**Files:**
- Modify: `KharchaKit/Sources/KharchaKit/Math/ActivitySeries.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/ActivitySeriesTests.swift`

**Interfaces:**
- Consumes: `ActivityPeriod` (`.week` / `.month` / `.year`), already defined at
  the top of `ActivitySeries.swift`.
- Produces: `ActivitySeries.rung(forScale: Double, from: ActivityPeriod) -> ActivityPeriod`.
  Task 5 and Task 6 call this.

- [ ] **Step 1: Write the failing test**

Add to `ActivitySeriesTests.swift`, above the `// MARK: - Continuous series` marker:

```swift
// MARK: - Pinch zoom rungs

@Test func zoomingInFromMonthLandsOnWeek() {
    // A pinch-out gesture (scale > 1) means "show me less time, in more detail".
    #expect(ActivitySeries.rung(forScale: 2.0, from: .month) == .week)
}

@Test func zoomingOutFromMonthLandsOnYear() {
    #expect(ActivitySeries.rung(forScale: 0.4, from: .month) == .year)
}

@Test func smallScaleChangesDoNotChangeRung() {
    // Fingers wobble. A gesture that barely moved must not flip the scope,
    // or the chart would re-bucket every time the user rests two fingers on it.
    #expect(ActivitySeries.rung(forScale: 1.1, from: .month) == .month)
    #expect(ActivitySeries.rung(forScale: 0.9, from: .month) == .month)
}

@Test func rungsDoNotRunPastTheEndsOfTheLadder() {
    // Week is the most zoomed-in rung and year the most zoomed-out; pinching
    // harder at either end must clamp rather than wrap around.
    #expect(ActivitySeries.rung(forScale: 8.0, from: .week) == .week)
    #expect(ActivitySeries.rung(forScale: 0.1, from: .year) == .year)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd KharchaKit && swift test --filter zoomingInFromMonth`
Expected: FAIL — `type 'ActivitySeries' has no member 'rung'`

- [ ] **Step 3: Write minimal implementation**

In `ActivitySeries.swift`, add inside `public enum ActivitySeries`, directly after
the `spendLevel` function:

```swift
    /// Scale beyond which a pinch counts as a deliberate zoom rather than a wobble.
    /// Below it the rung is unchanged, so resting two fingers on the chart does
    /// nothing.
    private static let rungThreshold = 1.5

    /// The rung a pinch lands on when the fingers lift.
    ///
    /// `scale` is the live magnification: greater than 1 means the fingers spread
    /// (zoom in, less time in more detail), less than 1 means they pinched
    /// together. Movement inside the threshold keeps the current rung, and the
    /// ladder clamps at both ends rather than wrapping.
    public static func rung(forScale scale: Double, from current: ActivityPeriod) -> ActivityPeriod {
        let ladder: [ActivityPeriod] = [.week, .month, .year]   // in → out
        guard let index = ladder.firstIndex(of: current) else { return current }
        let step: Int
        if scale >= rungThreshold {
            step = -1                       // zoom in, toward .week
        } else if scale <= 1 / rungThreshold {
            step = 1                        // zoom out, toward .year
        } else {
            step = 0
        }
        let target = min(max(index + step, 0), ladder.count - 1)
        return ladder[target]
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd KharchaKit && swift test --filter zoomin`
Expected: PASS, 4 tests.

Then the whole suite: `cd KharchaKit && swift test`
Expected: exactly one failure, `loadPopulatesMonthTotalsAndRecent` (see Global Constraints).

- [ ] **Step 5: Commit**

```bash
git add KharchaKit/Sources/KharchaKit/Math/ActivitySeries.swift \
        KharchaKit/Tests/KharchaKitTests/ActivitySeriesTests.swift
git commit -m "feat: snap a pinch scale to the nearest chart zoom rung"
```

---

### Task 3: Bound the continuous series so a decade of days is not built eagerly

The spec flags that `continuousBars` builds one bar per day across the whole
domain. Scrolling to ±5 years makes that ~3,650 objects on every reload. Bound it.

**Files:**
- Modify: `KharchaKit/Sources/KharchaKit/Math/ActivitySeries.swift:continuousBars`
- Test: `KharchaKit/Tests/KharchaKitTests/ActivitySeriesTests.swift`

**Interfaces:**
- Consumes: `ActivitySeries.continuousBars(_:period:now:calendar:)`, current
  signature `([TxnRow], ActivityPeriod, Date, Calendar) -> [ActivityBar]`.
- Produces: same function with an added parameter —
  `continuousBars(_ txns: [TxnRow], period: ActivityPeriod, now: Date, calendar: Calendar, maxBuckets: Int = 800) -> [ActivityBar]`.
  Existing callers keep working via the default. Task 5 relies on the default.

- [ ] **Step 1: Write the failing test**

Add to `ActivitySeriesTests.swift`, after `continuousMonthBarsExtendToFutureDatedTransactions`:

```swift
@Test func continuousBarsAreCappedSoALongHistoryDoesNotBuildThousandsOfBuckets() throws {
    // A ledger spanning years must not turn into one ActivityBar per day across
    // the whole range on every reload. The cap keeps the series bounded; the
    // window stays anchored on `now`, which is where the chart opens.
    let txns = [
        row(100, .expense, d(2018, 1, 5)),
        row(100, .expense, d(2026, 8, 5))
    ]
    let bars = ActivitySeries.continuousBars(txns, period: .month,
                                             now: d(2026, 8, 15),
                                             calendar: testCal, maxBuckets: 100)
    #expect(bars.count <= 100)
    // The window still covers today, so the chart has somewhere to land.
    let last = try #require(bars.last).date
    #expect(last >= testCal.startOfDay(for: d(2026, 8, 1)))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd KharchaKit && swift test --filter continuousBarsAreCapped`
Expected: FAIL — `extra argument 'maxBuckets' in call`

- [ ] **Step 3: Write minimal implementation**

In `ActivitySeries.swift`, change the signature and clamp the start. Replace the
existing `continuousBars` declaration line and the block that computes `start`:

```swift
    public static func continuousBars(_ txns: [TxnRow], period: ActivityPeriod, now: Date, calendar: Calendar, maxBuckets: Int = 800) -> [ActivityBar] {
```

and after `let end = bounding.dateInterval(of: unit, for: latest)!.end`, insert:

```swift
        // Cap the series so a multi-year ledger does not become one bucket per day
        // across the whole range. The window keeps its most recent end — that is
        // where the chart opens — and drops the oldest buckets beyond the cap.
        let bucket: Calendar.Component = (period == .year) ? .month : .day
        let available = calendar.dateComponents([bucket], from: start, to: end).value(for: bucket) ?? 0
        let clampedStart = available > maxBuckets
            ? calendar.date(byAdding: bucket, value: -maxBuckets, to: end)!
            : start
```

Then replace the two uses of `start` in the `switch period` block below with
`clampedStart`:

```swift
        switch period {
        case .week, .month:
            let days = calendar.dateComponents([.day], from: clampedStart, to: end).day!
            return dailyBars(txns, from: clampedStart, days: days, calendar: calendar)
        case .year:
            let months = calendar.dateComponents([.month], from: clampedStart, to: end).month!
            return monthlyBars(txns, from: clampedStart, months: months, calendar: calendar)
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd KharchaKit && swift test --filter continuous`
Expected: PASS — the new test plus the five existing `continuous*` tests, which
must all still pass because the default `maxBuckets: 800` exceeds their ranges.

Then: `cd KharchaKit && swift test`
Expected: exactly one failure, `loadPopulatesMonthTotalsAndRecent`.

- [ ] **Step 5: Commit**

```bash
git add KharchaKit/Sources/KharchaKit/Math/ActivitySeries.swift \
        KharchaKit/Tests/KharchaKitTests/ActivitySeriesTests.swift
git commit -m "perf: cap the continuous bar series so long ledgers stay bounded"
```

---

### Task 4: Detect an empty visible range

Drives the `No transactions in <period>` overlay.

**Files:**
- Modify: `KharchaKit/Sources/KharchaKit/Math/ActivitySeries.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/ActivitySeriesTests.swift`

**Interfaces:**
- Consumes: `ActivitySummary` (has `expense`, `income`, `start`, `barCount`).
- Produces: `ActivitySummary.isEmpty: Bool`. Task 7 reads it.

- [ ] **Step 1: Write the failing test**

Add to `ActivitySeriesTests.swift`, after `summaryWindowLengthFollowsTheCalendarMonthNotAFixedSpan`:

```swift
@Test func summaryKnowsWhenItsWindowHoldsNothingAtAll() {
    // Scrolling into an unused year must be able to say so, rather than showing
    // a blank plot the user has to interpret.
    let empty = ActivitySeries.summary([], period: .month,
                                       containing: d(2021, 3, 15), calendar: testCal)
    #expect(empty.isEmpty)
}

@Test func summaryIsNotEmptyWhenOnlyIncomeLandsInTheWindow() {
    // Income with no spending is still activity. Only a window with neither
    // counts as empty.
    let txns = [row(3_000_000, .income, d(2026, 8, 25))]
    let s = ActivitySeries.summary(txns, period: .month,
                                   containing: d(2026, 8, 15), calendar: testCal)
    #expect(!s.isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd KharchaKit && swift test --filter summaryKnowsWhenItsWindow`
Expected: FAIL — `value of type 'ActivitySummary' has no member 'isEmpty'`

- [ ] **Step 3: Write minimal implementation**

In `ActivitySeries.swift`, inside `public struct ActivitySummary`, after the
`changePercent` computed property:

```swift
    /// True when the window holds no activity of any kind. Distinct from a
    /// no-spend day, which is a real day that happened to cost nothing — this is
    /// a stretch of timeline with nothing in it, and says so on the chart.
    public var isEmpty: Bool { expense == 0 && income == 0 }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd KharchaKit && swift test --filter summary`
Expected: PASS, all `summary*` tests.

Then: `cd KharchaKit && swift test`
Expected: exactly one failure, `loadPopulatesMonthTotalsAndRecent`.

- [ ] **Step 5: Commit**

```bash
git add KharchaKit/Sources/KharchaKit/Math/ActivitySeries.swift \
        KharchaKit/Tests/KharchaKitTests/ActivitySeriesTests.swift
git commit -m "feat: let a chart summary report an empty visible range"
```

---

### Task 5: View model — live zoom scale and settling to a rung

**Files:**
- Modify: `KharchaKit/Sources/KharchaKit/ViewModels/HistoryViewModel.swift`
- Test: `KharchaKit/Tests/KharchaKitTests/HistoryViewModelTests.swift`

**Interfaces:**
- Consumes: `ActivitySeries.rung(forScale:from:)` from Task 2;
  `HistoryViewModel.State.chartPeriod`, `chartAnchor`, `setChartPeriod(_:calendar:)`
  which all already exist.
- Produces:
  - `HistoryViewModel.State.zoomScale: Double` (1.0 at rest)
  - `HistoryViewModel.setZoomScale(_ scale: Double)` — synchronous, no reload
  - `HistoryViewModel.settleZoom(calendar: Calendar) async`
  Task 6 calls all three.

- [ ] **Step 1: Write the failing test**

Add to `HistoryViewModelTests.swift`, before the closing `}` of the suite:

```swift
    @Test
    @MainActor
    func pinchingScalesLiveThenSettlesOntoARung() async throws {
        // Mid-gesture only the scale moves — re-bucketing while the fingers are
        // down would pop the bars under them. The rung changes once, on release.
        let store = try makeStore()
        _ = try await store.addTxn(amount: 10_000, kind: .expense, categoryID: nil,
                                   note: nil, date: d(2026, 8, 10), source: .manual)
        let vm = HistoryViewModel(store: store)
        await vm.load(calendar: testCal)
        await vm.setChartPeriod(.month, calendar: testCal)

        vm.setZoomScale(2.0)
        #expect(vm.state.zoomScale == 2.0)
        #expect(vm.state.chartPeriod == .month)     // not yet re-bucketed

        await vm.settleZoom(calendar: testCal)
        #expect(vm.state.chartPeriod == .week)      // snapped in
        #expect(vm.state.zoomScale == 1.0)          // scale reset for the next pinch
    }

    @Test
    @MainActor
    func settlingAZoomKeepsTheAnchorSoYouStayInTheMonthYouWereLookingAt() async throws {
        // Zooming is a change of detail, not of place. Landing back on "today"
        // would throw away wherever the user had scrolled to.
        let store = try makeStore()
        _ = try await store.addTxn(amount: 10_000, kind: .expense, categoryID: nil,
                                   note: nil, date: d(2026, 7, 10), source: .manual)
        let vm = HistoryViewModel(store: store)
        await vm.load(calendar: testCal)
        await vm.setChartAnchor(d(2026, 7, 15), calendar: testCal)

        vm.setZoomScale(2.0)
        await vm.settleZoom(calendar: testCal)

        #expect(testCal.component(.month, from: vm.state.chartAnchor) == 7)
        let start = try #require(vm.state.chartSummary?.start)
        #expect(testCal.component(.month, from: start) == 7)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd KharchaKit && swift test --filter pinchingScalesLive`
Expected: FAIL — `value of type 'HistoryViewModel.State' has no member 'zoomScale'`

- [ ] **Step 3: Write minimal implementation**

In `HistoryViewModel.swift`, add to `State` after `settledAnchor`:

```swift
        /// Live magnification while a pinch is in flight, 1.0 at rest. Scales the
        /// chart's visible domain only — bars keep their granularity until the
        /// fingers lift, so nothing re-buckets under them mid-gesture.
        public var zoomScale: Double = 1.0
```

Add these two methods after `setChartPeriod`:

```swift
    /// Track the pinch. Deliberately synchronous and free of any reload: this
    /// fires continuously while the fingers move, and must cost nothing but a
    /// layout pass.
    public func setZoomScale(_ scale: Double) {
        state.zoomScale = scale
    }

    /// Called when the fingers lift. Snaps to the nearest rung and re-buckets
    /// once. `chartAnchor` is untouched, so zooming changes detail, not place.
    public func settleZoom(calendar: Calendar = .current) async {
        let target = ActivitySeries.rung(forScale: state.zoomScale, from: state.chartPeriod)
        state.zoomScale = 1.0
        guard target != state.chartPeriod else { return }
        await setChartPeriod(target, calendar: calendar)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd KharchaKit && swift test --filter "pinchingScalesLive|settlingAZoomKeeps"`
Expected: PASS, 2 tests.

Then: `cd KharchaKit && swift test`
Expected: exactly one failure, `loadPopulatesMonthTotalsAndRecent`.

- [ ] **Step 5: Commit**

```bash
git add KharchaKit/Sources/KharchaKit/ViewModels/HistoryViewModel.swift \
        KharchaKit/Tests/KharchaKitTests/HistoryViewModelTests.swift
git commit -m "feat: track pinch scale live and settle it onto a zoom rung"
```

---

### Task 6: Wire the pinch to the card and delete the segmented control

The view change. No unit tests — SwiftUI gestures are not unit-testable; this task
is verified by building and by the on-device checks in Task 8.

**Files:**
- Modify: `App/Views/HistoryView.swift`
- Modify: `App/Views/ActivityCharts.swift`

**Interfaces:**
- Consumes: `vm.state.zoomScale`, `vm.setZoomScale(_:)`, `vm.settleZoom(calendar:)`
  from Task 5; `ActivityBarChart`'s existing `period`, `allowance`,
  `scrollPosition`, `selectedDate` parameters.
- Produces: `ActivityBarChart` gains `var zoomScale: Double = 1.0`, declared
  immediately after `allowance` so the memberwise initialiser order is
  `bars, unit, selectedDate, period, allowance, zoomScale, scrollPosition`.
  Task 7 adds one more parameter after `zoomScale`.

- [ ] **Step 1: Scale the visible domain by the live pinch**

In `ActivityCharts.swift`, add the property after `allowance`:

```swift
    /// Live pinch magnification. Widens or narrows the visible window while the
    /// fingers move; the bars themselves do not re-bucket until release.
    var zoomScale: Double = 1.0
```

Then divide the domain by it — replace the body of `visibleDomain`:

```swift
    private var visibleDomain: TimeInterval {
        let day: TimeInterval = 24 * 60 * 60
        let base: TimeInterval
        switch period {
        case .week:  base = 7 * day
        case .month: base = 31 * day
        case .year:  base = 365 * day
        }
        // Fingers spreading (scale > 1) means less time on screen, in more detail.
        // Clamped so a violent pinch cannot collapse the domain to nothing.
        return base / min(max(zoomScale, 0.25), 4.0)
    }
```

- [ ] **Step 2: Delete the Picker and attach the gesture**

In `HistoryView.swift`, in `analyticsSection`, delete the whole `Picker("Period", …)`
block and the `Spacer()` before it, leaving the label as:

```swift
            } label: {
                Label("Analytics", systemImage: "chart.bar.xaxis")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
```

Pass the scale into the chart — add one argument to the existing
`ActivityBarChart(...)` call, between `allowance:` and `scrollPosition:`:

```swift
                    zoomScale: vm.state.zoomScale,
```

Then attach the gesture to the `DisclosureGroup`. Add this modifier directly on
the `DisclosureGroup`, before its `.listRowInsets` or the closing of the `Section`:

```swift
            // Pinch anywhere on the card, not just the chart: the chart is only
            // ~200pt tall and already owns a horizontal scroll view. Two fingers
            // keeps this disjoint from both the list's vertical drag and the
            // chart's horizontal one.
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { vm.setZoomScale($0) }
                    .onEnded { _ in Task { await vm.settleZoom() } }
            )
```

**If Task 1's spike found `simultaneousGesture` insufficient**, replace this
modifier with the `UIViewRepresentable` overlay recorded there instead.

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -scheme Kharcha -destination 'generic/platform=iOS Simulator' \
  OBJROOT=/tmp/kzoom/obj SYMROOT=/tmp/kzoom/sym build 2>&1 | grep -E "error:|BUILD"
```
Expected: `** BUILD SUCCEEDED **`

If it fails with `argument 'scrollPosition' must precede argument 'zoomScale'`,
the property was declared in the wrong place — move `zoomScale` above
`@Binding var scrollPosition` in `ActivityBarChart`.

- [ ] **Step 4: Confirm the model suite is untouched**

Run: `cd KharchaKit && swift test`
Expected: exactly one failure, `loadPopulatesMonthTotalsAndRecent`.

- [ ] **Step 5: Commit**

```bash
git add App/Views/HistoryView.swift App/Views/ActivityCharts.swift
git commit -m "feat: pinch the analytics card to zoom, replacing the W/M/Y picker"
```

---

### Task 7: Transient scope indicator, empty-range overlay, and accessibility

Three overlays on one view, built together because they share the same
`.overlay` on the chart and would otherwise fight for it.

**Files:**
- Modify: `App/Views/ActivityCharts.swift`
- Modify: `App/Views/HistoryView.swift`

**Interfaces:**
- Consumes: `ActivitySummary.isEmpty` from Task 4; `zoomScale` from Task 6.
- Produces: `ActivityBarChart` gains `var summary: ActivitySummary?`, declared
  immediately after `zoomScale`, so the initialiser order becomes
  `bars, unit, selectedDate, period, allowance, zoomScale, summary, scrollPosition`.

- [ ] **Step 1: Add the scope name and the two overlays**

In `ActivityCharts.swift`, add after `zoomScale`:

```swift
    /// Totals for the visible window. Only used to say when it holds nothing.
    var summary: ActivitySummary?
```

Add these helpers next to `barColor(for:)`:

```swift
    /// Human name for the current rung, shown transiently while pinching.
    private var scopeName: String {
        switch period {
        case .week:  return String(localized: "Week")
        case .month: return String(localized: "Month")
        case .year:  return String(localized: "Year")
        }
    }

    /// True while a pinch is actually in flight, not merely resting.
    private var isPinching: Bool { abs(zoomScale - 1.0) > 0.02 }
```

- [ ] **Step 2: Attach the overlays to the chart**

In `ActivityBarChart.body`, replace the final `.frame(height: 200)` with:

```swift
        .frame(height: 200)
        // Scope shown only while it is changing — the HUD pattern, so the screen
        // carries no permanent scope chrome.
        .overlay {
            if isPinching {
                Text(scopeName)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isPinching)
        // An empty stretch of timeline says so, rather than leaving a blank plot
        // for the user to interpret.
        .overlay {
            if summary?.isEmpty == true {
                Text("No transactions in this period")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
```

- [ ] **Step 3: Add the non-gesture route for VoiceOver**

Append to the same chain, after the overlays:

```swift
        // Pinch cannot be the only way to change scope: VoiceOver, Switch Control
        // and Voice Control users cannot perform it. Swipe up/down does the same.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Spending chart, \(scopeName)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onZoomIn?()
            case .decrement: onZoomOut?()
            @unknown default: break
            }
        }
```

and declare the two callbacks after `summary`:

```swift
    /// Non-gesture zoom, for assistive technologies. Both are required whenever
    /// the chart is interactive.
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?
```

- [ ] **Step 4: Pass the new arguments from HistoryView**

In `HistoryView.swift`, in the `ActivityBarChart(...)` call, add after `zoomScale:`:

```swift
                    summary: vm.state.chartSummary,
                    onZoomIn: {
                        vm.setZoomScale(2.0)
                        Task { await vm.settleZoom() }
                    },
                    onZoomOut: {
                        vm.setZoomScale(0.4)
                        Task { await vm.settleZoom() }
                    },
```

- [ ] **Step 5: Build and commit**

Run:
```bash
xcodebuild -scheme Kharcha -destination 'generic/platform=iOS Simulator' \
  OBJROOT=/tmp/kzoom/obj SYMROOT=/tmp/kzoom/sym build 2>&1 | grep -E "error:|BUILD"
```
Expected: `** BUILD SUCCEEDED **`

```bash
git add App/Views/ActivityCharts.swift App/Views/HistoryView.swift
git commit -m "feat: transient scope HUD, empty-range message, and accessible zoom"
```

---

### Task 8: On-device verification

Nothing here is unit-testable. These are the checks that decide whether the
feature ships or goes back to design.

**Files:** none modified unless a check fails.

**Interfaces:**
- Consumes: everything from Tasks 1-7.
- Produces: a pass/fail list appended to this plan.

- [ ] **Step 1: Build to a real device**

Open `Kharcha.xcodeproj` in Xcode 26.4.1, select a device, run. A simulator is
not sufficient — pinch feel and gesture arbitration differ.

- [ ] **Step 2: Work through the checks**

1. Pinch out over the chart → rung goes Month → Week, bars become one week.
2. Pinch in → Month → Year, bars become months.
3. Pinch at the ends → nothing happens, no wrap-around.
4. Mid-gesture, do the thin bars read as intentional or broken? *Spec accepts
   briefly-thin bars; if they look broken, that is a finding.*
5. The scope HUD appears during the pinch and fades ~1s after release.
6. One-finger vertical drag still scrolls the list.
7. One-finger horizontal drag still scrolls the chart.
8. Tap on a bar still selects it.
9. Scroll into an unused year → "No transactions in this period" appears.
10. VoiceOver on: focus the chart, swipe up/down changes scope and announces it.
11. At the Month rung with ~31 bars, are the amount labels legible or a mess?
    *The spec expects them to need thinning; confirm how bad it is.*

- [ ] **Step 3: Record findings and stop**

Append results to this plan under this task. Any failure in checks 6, 7, 8 or 10
is a blocker and needs redesign, not a patch — report rather than fixing in place.

```bash
git add docs/superpowers/plans/2026-09-03-chart-pinch-zoom.md
git commit -m "docs: record on-device verification results for chart zoom"
```

---

## Deferred

Not in this plan, deliberately:

- **Adaptive label density at the Month rung.** The spec accepts that ~31 labels
  will not fit, and check 11 measures how bad it is. Fixing it is a separate piece
  of work once we know whether it needs thinning, peak-only labels, or nothing.
- **The ±5 year domain question.** Task 3 caps the series at 800 buckets, which
  bounds the cost. Whether the domain should span a full ±5 years regardless of
  data, or clamp to the data range plus a margin, is the spec's open question and
  is not settled here.
