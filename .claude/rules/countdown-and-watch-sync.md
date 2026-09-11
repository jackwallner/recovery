---
paths:
  - "RechargeWatch/**/*"
  - "RechargeWatchWidget/**/*"
  - "RechargeWidget/**/*"
  - "Recharge/App.swift"
  - "Recharge/Info.plist"
  - "Recharge/Views/EffortPromptSheet.swift"
  - "Shared/Utilities/CountdownTimeline.swift"
  - "Shared/Utilities/CountdownFormat.swift"
  - "Shared/Utilities/ComplicationCopy.swift"
  - "Shared/Services/PhoneWatchSession.swift"
  - "Shared/Services/HealthKitService.swift"
  - "Shared/Models/RecoverySnapshot.swift"
  - "RechargeTests/CountdownTimelineTests.swift"
  - "RechargeTests/CountdownFormatTests.swift"
  - "RechargeTests/ComplicationCopyTests.swift"
  - "RechargeTests/RecoverySnapshotTests.swift"
  - "RechargeTests/SnapshotSyncStateTests.swift"
---

# Recharge: the countdown, the Watch, and background sync

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here. Section names cited from other files are listed in the CLAUDE.md index.

### The countdown timeline
The one piece with no precedent in the fleet. Every other complication here
renders a cumulative daily number that only grows, and one entry with an hourly
refresh is enough. A countdown decays toward a fixed timestamp, so
`CountdownTimeline` pre-computes the whole descent: hourly, then every 15 minutes
through the final two hours, an entry exactly at `readyAt`, and one after it so
the face flips to Ready even if the system never refreshes. **Views must render
from `entry.date`, never from `Date.now`.**

Two things went wrong on the wrist and both looked like a broken complication:

- **The value did not tick.** `CountdownFormat.compactRemaining` returned a bare
  `"\(days)d"` above 24 hours, which is where most of the app's range lives: a
  72-hour window read `3d` for a full day, then `2d` for a full day, then `1d`
  for a full day, while the timeline dutifully carried seventy hourly entries
  that all rendered the same three characters. It steps down through `2d 23h`,
  `23h`, `1h 20m`, `18m` now, capped at six characters so a circular or corner
  slot still fits it. The guarantee is
  `testTheCompactCountdownChangesAtLeastOnceAnHourAcrossTheWholeRange`, asserted
  over every minute of the range rather than at sample points — the old tests all
  passed because none of them asked whether two entries an hour apart *differ*.
- **A fresh install rendered `--`, and stayed that way.** Two devices, two App
  Group containers, so a snapshot has to cross WatchConnectivity and be written
  to the Watch's own disk. The extension cannot take that delivery itself — a
  widget extension is not a running process that can be sent anything, it is
  spun up to answer "give me a timeline" and torn down, so whatever it needs must
  already be on disk. **The user should never have to open the Watch app for
  that to happen**, and `WatchAppDelegate` is the whole reason they do not: the
  system wakes it in the background to take delivery, and it writes the App
  Group and reloads the timelines.

  `handle(_ backgroundTasks:)` broke that chain in three ways and between them
  made "open the Watch app first" the normal case. It completed every task
  immediately, including `WKWatchConnectivityRefreshBackgroundTask` — which is
  the system saying "stay alive, data is arriving", and completing it before
  `hasContentPending` clears lets the payload be dropped. It never scheduled the
  next `WKApplicationRefreshBackgroundTask`, and watchOS background refresh is a
  chain, so the app went quiet after the first wake. And it handed every task
  type the same completion call, which is wrong for a snapshot task. Fixed, with
  `PhoneWatchSession.waitForPendingContent` holding the connectivity task open.

  `ComplicationCopy.DataState.neverSynced` covers the window before the first
  delivery lands and says "Open Recharge to set up". That window should be brief,
  and if a user reports it persisting, the background-wake path is what to look
  at, not the copy.

- **The chain starts on the phone, and its first link was missing.**
  `HealthKitService.enableBackgroundDelivery` installs the observer queries, and
  it was reachable only from the scene's `.task`, by way of
  `synchronizeAuthorization`. A scene is not connected when HealthKit background
  delivery relaunches the app, so the wake a finished workout generates arrived
  at a process with no observer running and did nothing: the phone never
  rescored, never published, and every downstream link — application context,
  Watch wake, App Group write, timeline reload — was waiting on a push that was
  never sent. Apple's guidance is to re-execute observer queries as early in
  launch as possible, so it runs from `RechargeApp.init` now, gated on
  `hasCompletedSetup && !hasDeferredHealthAccess`. It is idempotent
  (`installedObserverTypes` de-duplicates), so the scene path calling it again
  costs nothing.

  **Moving only the observer left the next link behind.** `sendSnapshot` is
  guarded on `activationState == .activated` and returns silently otherwise,
  and `PhoneWatchSession.activate()` was itself called only from the scene's
  `.task` — so a background wake recalculated correctly, wrote the phone's App
  Group, updated the iOS widgets, and published to nobody. The wrist heard
  nothing until the app was next opened by hand, which is the same symptom with
  a different cause one step down the chain. Activation is in `RechargeApp.init`
  now, where Apple says to put it, and `waitForActivation` holds the
  `BGAppRefreshTask` and the observer refresh open until it lands rather than
  trusting the `activationDidCompleteWith` republish, which only helps while the
  process is still alive.

  The general shape is worth stating once: **every link in this chain is guarded
  by a silent `return`, and each one is only as good as the link before it.**
  HealthKit observer, `WCSession` activation, `updateApplicationContext`, the
  Watch's background task, the App Group write, the timeline reload. Fixing one
  and leaving the next in a scene callback moves the failure rather than
  removing it.

  `BGTaskSchedulerPermittedIdentifiers` and `UIBackgroundModes: fetch` were in
  `Info.plist` with nothing registering or submitting a task — a background mode
  the app claimed and did not use, which is also an App Review 2.5.4 problem.
  `com.jackwallner.recovery.refresh` is a real `BGAppRefreshTask` now, on the
  same 30-minute backstop cadence as the Watch's, and Vitals has had exactly
  this since the beginning.

- **A watch background task must not complete before the write lands, and two
  ways of getting that wrong survived the first fix.** `hasContentPending` going
  false means WatchConnectivity has *called its delegate*, not that anything is
  on disk: `forwardSnapshot` still has to hop to the main actor before
  `applyInboundSnapshot` writes the App Group, and completing the task in that
  gap suspends the app between "delivered" and "saved". `inflightApplies` is
  incremented on the delegate queue, before the hop, so `waitForPendingContent`
  can see deliveries that have not finished landing.

  The `WKApplicationRefreshBackgroundTask` case had the same shape as the bug it
  was written to fix: it called `activate()`, which is asynchronous, and
  completed. That task almost always runs in a *fresh* process — the app is
  killed between wakes — so it completed before the session finished activating,
  which made the backstop a no-op in precisely the case it exists for. And on
  that wake there is no pending content to wait for, so the replayed
  `receivedApplicationContext` is the only thing there is to apply and the
  `activationDidCompleteWith` hop that would have applied it loses the race by
  default. `applyReplayedContext` does it synchronously at the end of
  `waitForPendingContent`.

  That replay runs on every wake, so it is usually the *same* payload the wrist
  already holds, and `reloadAllTimelines` spends the budget the countdown needs.
  `applyInboundSnapshot` compares before reloading, and
  `testAReplayedSnapshotComparesEqualSoTheWakeCanSkipTheReload` pins the
  round-trip equality that comparison rests on.

- **"Never synced" was being inferred from the wrong question.** The complication
  asked `snapshot.hasSession`, so a user who had synced perfectly well but simply
  had not trained in four days was told to open Recharge and set it up, with
  nothing to set up and no way to clear it short of doing a workout. An empty
  snapshot and a *missing* one decode to the same value, so only the presence of
  the App Group key separates them: `RecoverySnapshotStore.loadIfPresent` and
  `hasEverSynced` are that distinction, and `load` keeps its forgiving behaviour
  for every caller that just wants something to draw. "No recent qualifying
  workout" is `noRecentWorkout`, and it already existed.

- **A late payload used to win.** The phone reaches the wrist by two routes with
  different delivery semantics (the application context is a latest-value-wins
  slot, `transferUserInfo` is a FIFO queue that drains on reconnect), so a
  transfer queued before an outage can arrive *after* a newer context. On screen
  that is a countdown jumping backwards to a window the user watched expire.
  `sentAt` was already on every payload as a cache-buster (`updateApplicationContext`
  no-ops on a byte-identical dict), and `applyInboundSnapshot` now believes it,
  against a high-water mark persisted in the App Group because the Watch app is
  killed between background wakes. The snapshot's own `calculatedAt` would be
  the more natural key and is the wrong one: `RecoverySnapshot.empty` carries
  `.distantPast`, and the phone legitimately publishes an empty snapshot when the
  last workout is deleted from Health, so ordering on it would refuse the one
  payload whose job is to clear the wrist. The reply to an explicit
  `requestSnapshot` bypasses the check, because it is current by construction,
  and it is the way out if a phone's clock ever moves backwards.

**Recharge's Watch app is the only one in the fleet that cannot read Health.**
`VitalsWatch` and `VO2MaxWatch` both carry `com.apple.developer.healthkit` and
compute their own numbers on the wrist, so their complications work with no
phone involvement at all and never depend on a background wake landing. That is
why they "just work" and this one is fussier, and it is a deliberate choice
here, not an oversight: the phone owns the model, and a watch recomputing it
could disagree with the phone about the same session.

The escape hatch is cheaper than it looks if it is ever needed. `Shared` is
compiled into `RechargeWatch` in full, so `RecoveryEngine`, `HealthKitService`
and `DataService` are already on the wrist, and `RechargeWatch/Info.plist`
already carries both Health usage strings. The missing pieces are the
entitlement and — the part that is actually the work — syncing
`effectiveMaxHeartRate`, `calibrationFactor`, `athleteProfile`, `ambiguousProfile`
and the tier, without which the watch would score against defaults and visibly
disagree with the phone. Do not take this path to fix a delivery bug; take it
only if mirroring is decided against on purpose.

### The RPE path is the only Watch → phone write
Everything else runs phone → Watch. The effort tap has to go the other way, so it
uses `PhoneWatchSession` (ported from the retired Headache Logger): `sendMessage`
when reachable, `transferUserInfo` otherwise, plus an App Group backstop queue.
The phone names the session needing an answer via the `pendingEffortSessionID`
App Group key, because the Watch has no workout history of its own.

### Staleness on the glance surfaces

- **Staleness reaches the glance surfaces, and it annotates rather than
  replaces.** `RecoverySnapshot.healthDataState` carries the fact across the App
  Group and WatchConnectivity, because a widget and a complication have no
  `RecoveryEngine` to ask and would otherwise show an old countdown as if it
  were current. Two rules, both of which were bugs first.

  **It does not blank the number.** `readyAt` was computed before the read
  failed and is still counting down correctly; a failed read says only that
  something *newer* might be missing from it. The first cut replaced the
  countdown everywhere with "Health paused" / "Retry", which threw away the one
  thing the surface knew in order to warn about the one thing it did not, and
  contradicted the phone, which keeps its countdown and adds
  `TodayView.freshness` under the date. Only `ComplicationCopy.secondary` and
  the iOS widget caption change; `primary`, `inline`, `rectangularTitle`, the
  ring, the gauge and the phase glyph are untouched.
  `testStaleHealthDataAnnotatesTheCountdownRatherThanReplacingIt` asserts that
  exactly one of the four strings differs from the synced version, and
  `testOnlyTheStatesWithNoModelReplaceTheValue` keeps `neverSynced` and
  `unreadable` on the other side of that line, since they genuinely have
  nothing to render.

  **It is not `lastImportFailed`.** One query fails routinely for reasons that
  have nothing to do with the user: HealthKit refuses protected reads while the
  device is locked, and both the observer and the `BGAppRefreshTask` fire on
  locked devices constantly. Publishing that straight through would have put a
  warning on the lock screen at the moment the countdown was most correct.
  `HealthDataState.resolve` debounces on `staleAfter` (6h), and
  `lastSuccessfulImport` is mirrored into the App Group because it is otherwise
  in-memory and a background wake usually runs in a fresh process, so every
  cold launch that failed its first read would look like an app that had never
  read anything. The phone still reports every failed attempt, because it has a
  scene, a pull-to-refresh, and room for a line.
