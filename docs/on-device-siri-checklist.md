# On-Device Siri Verification Checklist

Siri / App Intents cannot be exercised meaningfully in the Simulator — there is
no Siri, no Shortcuts vocabulary snapshot, and no lock-screen authentication
state to test against (spec `2026-08-14-kharcha-app-design.md` §9: "Siri
end-to-end is manual on-device"). This checklist is the manual pass a physical
iPhone must go through before a release that touches `KharchaShortcuts`,
`KharchaIntentsExtension`, or `NotificationScheduler`. Nothing here is
automatable; check each box by hand and record the device/iOS version used.

Device used: ______________________  iOS version: ______________________
Date: ______________________  Tester: ______________________

## 0. Install (personal-team signing note)

The project's app-group identifier is `group.com.manish.kharcha`
(`App/Kharcha.entitlements`, `Extension/KharchaExtension.entitlements`,
`project.yml`). App Group capabilities require an Apple Developer **team ID**
— a free personal-team signing account cannot provision an arbitrary
`group.com.manish.kharcha` unless that literal group already exists under the
paid account that owns it.

- [ ] If installing under a **paid Apple Developer Program team** that already
      owns/can provision `group.com.manish.kharcha`: no change needed, install
      via Xcode → Signing & Capabilities → set the team → Run.
- [ ] If installing under a **personal (free) team** for local testing:
      rename the group in **three places** before building —
      `project.yml` (`com.apple.security.application-groups` under both the
      `Kharcha` and `KharchaIntentsExtension` targets) and
      `KharchaContainerFactory.appGroupID` (`KharchaKit/Sources/KharchaKit/Store/KharchaContainerFactory.swift`)
      — to a group ID Xcode can auto-provision for that personal team (Xcode
      normally offers to create `group.<bundle-id-prefix>.<name>` automatically
      when you check the App Groups capability with automatic signing). Run
      `xcodegen generate` after editing `project.yml`, then rebuild. **Do not
      commit this rename** — it's a local-only workaround; revert before
      pushing.
- [ ] Confirm both the main app and `KharchaIntentsExtension` show the same
      resolved app-group ID in Signing & Capabilities before testing anything
      below — a mismatch here silently makes the extension read an empty store
      (each side gets its own container instead of sharing one).

## 1. Shortcuts app shows all 8 Kharcha shortcuts

Open **Shortcuts.app** → **Kharcha** app section (or search "Kharcha"). Confirm
all 8 appear with their `shortTitle` (`App/KharchaShortcuts.swift`):

- [ ] Log Expense
- [ ] Log Income
- [ ] Spending
- [ ] Budget
- [ ] Bill Reminder
- [ ] Log Loan
- [ ] Settle Up
- [ ] Debts

If fewer than 8 appear, force-quit Shortcuts and Kharcha, relaunch Kharcha once
(registers `AppShortcutsProvider`), and recheck — see §5 vocabulary-snapshot
finding below.

## 2. Each phrase, spoken twice (app killed / app backgrounded)

For every phrase below, say it to Siri twice on two separate app-lifecycle
states, and confirm the result each time (not just "Siri understood" — read
the actual snippet/spoken response for correctness):

| Intent | Phrase | Killed | Backgrounded |
|---|---|---|---|
| LogExpenseIntent | "Log an expense in Kharcha" | [ ] | [ ] |
| LogExpenseIntent | "Log lunch spending in Kharcha" (fills `$category`) | [ ] | [ ] |
| LogIncomeIntent | "I got paid in Kharcha" | [ ] | [ ] |
| SpendingQueryIntent | "How much did I spend in Kharcha" | [ ] | [ ] |
| BudgetStatusIntent | "How is my budget in Kharcha" | [ ] | [ ] |
| AddReminderIntent | "Add a bill reminder in Kharcha" | [ ] | [ ] |
| LogDebtIntent | "I gave money to <friend> in Kharcha" | [ ] | [ ] |
| LogDebtIntent | "I took money from <friend> in Kharcha" | [ ] | [ ] |
| SettleDebtIntent | "<friend> paid me back in Kharcha" | [ ] | [ ] |
| DebtQueryIntent | "Who owes me money in Kharcha" | [ ] | [ ] |

"Killed" = swipe Kharcha out of the app switcher immediately before speaking.
"Backgrounded" = leave Kharcha open in the background (press Home once) before
speaking. The intents run in `.background` mode (spec §5) — the app must
**never** visibly open for any of these unless the result card is tapped.

## 3. Locked-device behavior (spec §8)

- [ ] **Locked-device logging works** — lock the phone, then say "Log an
      expense in Kharcha" (or income/loan). Siri should accept the log
      (`authenticationPolicy` is permissive for logging) without prompting to
      unlock.
- [ ] **Locked-device query asks to unlock** — lock the phone, then say "How
      much did I spend in Kharcha" / "Who owes me money in Kharcha". Siri must
      require the device to be unlocked before reading totals or debt lists
      back — confirm it prompts for unlock rather than speaking the numbers.

## 4. Notifications

- [ ] Add (or edit) a recurring rule / debt due date so it falls due within
      the next few minutes (well inside `remindDaysBefore`'s window — set
      `remindDaysBefore` to 0 and `dayOfMonth` to today, or set a debt
      `dueDate` a couple minutes out). Background or lock the app and confirm
      the local notification fires at the expected time with the right title
      and body (`NotificationScheduler.resync` → `ReminderPlanner.plan`).
- [ ] Confirm stale notifications are cleared: delete the rule/debt before it
      fires, relaunch the app once (triggers `resync`), and confirm the
      notification does **not** fire.

## 5. Auto-log catch-up after skipping a day

`AppBootstrap.runAutoLogCatchUp` only runs on launch, comparing "now" against
the last-recorded catch-up date — this can't be exercised in one sitting in
the Simulator with a normal clock, so verify it on-device across a real day
boundary:

- [ ] Create a recurring rule with `autoLog` enabled and `dayOfMonth` set to
      **yesterday** (or set the device clock forward a day in Settings, launch
      once to let it register "now", then set the clock back — record which
      method was used).
- [ ] Force-quit the app, relaunch it, and confirm a `Txn` for the skipped
      occurrence was auto-logged (check Home's recent list / History) rather
      than silently dropped or double-logged.
- [ ] Repeat the relaunch a second time immediately after — confirm no
      duplicate transaction is created for the same occurrence.

## 6. Plan-2 findings — device-only reproductions

These were called out during Siri phrase design (spec §5, "lessons from the
GME iOS 27 findings") specifically because they never reproduce in the
Simulator or in `swift test` — only a live Siri session on a device surfaces
them:

- [ ] **Apple Cash phrase collision** — confirm none of the 8 shortcuts'
      phrases get intercepted by Apple Cash / Apple Pay instead of routing to
      Kharcha. The phrase set deliberately avoids "send money" and payment
      trigger words in favor of "log / spent / paid / gave / took"
      (`App/KharchaShortcuts.swift`); on-device, say each phrase once more
      specifically checking Siri doesn't offer an Apple Cash payment sheet or
      say "Do you want to send money to X" instead of running the Kharcha
      intent. If a collision appears, the offending phrase needs rewording,
      not just app-side testing — record the exact phrase and Siri's response.
- [ ] **Vocabulary snapshot delay after install** — immediately after a fresh
      install (not an update — delete the app first, or use a clean
      simulator/device), *before* opening the app, try an entity-parameter
      phrase ("Log lunch spending in Kharcha", "I gave money to Ram in
      Kharcha"). Confirm it may fail with "Kharcha isn't set up for that yet" /
      falls back to "app not supported" until iOS finishes snapshotting the
      vocabulary (can take a few minutes, sometimes needing one app launch to
      kick off). Then confirm the **parameter-free** fallback phrase for that
      same intent ("Log an expense in Kharcha") works immediately — this is
      the reason every intent keeps at least one parameter-free phrase (spec
      §5). Record how long the snapshot took before entity phrases started
      working.

## 7. Known limitations

These are accepted, understood gaps — not bugs to chase further right now.
Recorded here so a future reader doesn't rediscover them from scratch.

- **Extension-side notification scheduling is deferred.** The App Intents
  extension (`Extension/KharchaExtension.swift`) does not itself call
  `NotificationScheduler.resync` after an intent mutates data — only the main
  app does (on launch, and now on mutation from the views per the app-shell
  fix wave: adding/deleting a reminder, adding a debt with a due date). The net
  is app-launch/mutation resync: if you only ever interact with Kharcha
  through Siri and never open the app, reminder notifications can lag behind
  the true state until the app is next launched. Given Siri-only usage is a
  minority path and the app is expected to be opened regularly, this is an
  accepted gap rather than a blocker.
- **Cross-process fault staleness between background and foreground.**
  SwiftData `ExpenseStore` instances in the main app and the extension are
  separate processes reading the same App Group store. A sequence like
  background the app → settle a debt via Siri → foreground the app can show
  stale amounts for a moment because the foregrounded process's in-memory
  faults haven't refreshed yet. The app-shell fix wave adds a
  `.onReceive(...willEnterForegroundNotification)` → `vm.load()` on all 7
  screens specifically to correct this — **verification step:** on-device,
  background Kharcha, settle a debt (or log an expense) via Siri, then
  foreground the app and confirm the affected screen (FriendDetail / Home)
  shows the updated amount within roughly a second of returning to the
  foreground, not the stale pre-Siri value.
- **The auto-log watermark is an optimization, not the correctness
  guarantee.** `AutoLogRunner` (`KharchaKit/Sources/KharchaKit/Math/AutoLogRunner.swift`)
  persists a "last run" timestamp so it doesn't rescan all of history on every
  launch, but if that timestamp fails to persist (or is rolled back), catch-up
  will simply recompute the same missed-occurrence window — it will **not**
  double-log, because idempotency is enforced independently by checking
  `store.txnRows()` for an existing txn with the same note and the same
  start-of-day date before inserting. Do not read the watermark as a dedup
  mechanism; it only narrows the scan.

## Sign-off

- [ ] All sections above checked on at least one physical device.
- [ ] Any failures recorded above with device/iOS version, exact phrase, and
      Siri's actual response (not just pass/fail).
