# After performance analysis

**Date:** 2026-10-22
**Scope:** macOS menu bar app (`Sources/OpenCodeBar`) and iOS/iPadOS app
(`Sources/OpenCodeBarMobile`), plus the shared model/view code and the
XcodeGen project.
**Status:** implemented, built and tested.

## Summary

The work focused on four things that compound in a polling UI:

1. compute derived data once per refresh instead of once per view read;
2. stop rebuilding chart series and formatted strings that did not change;
3. render long lists and conversations lazily, with explicit data paging;
4. show stable skeleton layouts while data arrives and reduce redundant network
   work.

The largest measured wins were project ordering (~113× per evaluation), usage
series building (~9–11× per build, before counting the duplicate builds removed),
and number formatting (~37× per call).

## Changes by concept

### Derived data cached once per refresh

- Added `Models/ProjectOrdering.swift` — both stores now merge duplicate
  canonical records and order projects from a precomputed running count. This is
  `O(projects log projects + sessions)` instead of the previous
  `O(projects × sessions log projects)`.
- `AppState` and `MobileStore` now publish cached `runningSessions`,
  `recentSessions` and `orderedProjects`, plus private `runningByProject`,
  `subagentCounts` and `projectNames` maps. `rebuildDerived()` runs after the
  session list, running set or project map changes; `updateDerivedSession()`
  updates one cached row when a usage event moves cost/tokens.
- `activeSubagentCount(for:)`, `runningSessions(in:)` and `projectName(for:)` are
  now dictionary lookups instead of scans.

### Usage series and charts

- `UsageSeries.build` compares activity day strings (`yyyy-MM-dd`) directly and
  formats each day key once for the window, instead of parsing and formatting
  on every activity entry, session and day.
- `UsageSeries.bucketed` aggregates long ranges into at most 120 bars. The 30-day
  and 90-day charts are unchanged; `1Y` and `All` are readable and cheaper to
  draw. The iOS chart labels the bucket count as “bars”.
- `UsageTrendCard` and `TopProjectsCard`/`ProjectUsageCard` compute their series
  once per body instead of several times through computed properties.

### Formatting

- `Fmt.grouped` reuses one `NumberFormatter` instead of allocating one per call.

### Skeletons

- Added `Views/PerformanceViews.swift`, shared by both targets:
  `SkeletonBlock`, a Reduce-Motion-aware single shimmer for a group,
  session-row/list skeletons, stat-grid and chart skeletons, conversation,
  stats, changes, project-detail and usage-screen skeletons.
- Replaced spinner-only placeholders and empty states during the first load in:
  - macOS `LiveTab`, `ProjectsTab`, `UsageTab`, `SessionDetailView`,
    `ProjectDetailView`;
  - iOS `LiveView`, `ProjectsView`, `UsageView`, `SessionDetailView`,
    `ProjectDetailView`.
- Empty states still appear once the first poll has definitively returned no
  content; `isInitialLoading` distinguishes the two.

### Lazy loading and paging

- Conversations and prompt lists now use `LazyVStack` in both apps, so only
  visible message cards are built.
- Reaching the end of the loaded conversation automatically requests the next
  page; the explicit “Load earlier” button remains.
- The Live tab shows 20 recent sessions initially with a **Show more** control
  (previously a hard 20/30 slice). Projects show 20 initially with the same
  control and reset paging when the search/filter changes.
- iOS screen containers and the macOS project detail use `LazyVStack`.
- Project-file filtering computes its result once per body instead of three
  times (empty check, count and list).
- Session-detail continuation loads now request 30 messages instead of 100 once
  a first page exists, and skip the request entirely when the user is on Stats
  or Changes.

### Rendering

- `SessionMessage`, `MessagePart`, `MessagePart.Time` and
  `MessagePart.ToolState` are `Equatable`; message and prompt cards use
  `.equatable()`, so unchanged cards are skipped during streaming updates.
- File-change grouping is computed once per body, and the row builder no longer
  re-runs grouping for every row. `FileChangeCard` parses its patch once.
- `ChangeSummaryBar` computes additions, deletions and file count in one pass.

### Networking and scheduling

- `refreshAll` issues live, stats, history and usage concurrently.
- Missing active sessions are fetched concurrently with a task group instead of
  serially.
- Event-driven refreshes are throttled (one scheduled refresh, fire after
  750 ms) rather than a debouncing loop that a busy stream can starve.
- In-flight guards for Go usage and hub health; usage polling is time-guarded.
- Removed duplicate first-load requests from `PanelView.task` (macOS) and the
  extra unguarded usage request (iOS).
- iOS pauses polling and the event stream when the app enters the background,
  then reconnects and refreshes once when it becomes active.
- On a usage event, only the affected cached session row is rewritten; the
  whole list is not rebuilt.

### Memory

- On-demand caches (`projectDetails`, `sessionChanges`, `projectChanges`,
  `projectFiles`, `sessionStats`, `subagentLists`) keep at most 16 entries,
  evicting the least recently loaded and pinning the entry currently on screen.

## After measurements

Same benchmark as the baseline (`Scripts/perf-benchmark.sh`), same data set and
compiler.

| Path | Before | After | Improvement |
| --- | ---: | ---: | ---: |
| `UsageSeries.build` — 1,000 sessions, 365 days, `1Y` | 20.7 ms | **2.2 ms** | **~9.4×** |
| `UsageSeries.build` — same data, `All` | 46.1 ms | **4.1 ms** | **~11.3×** |
| Project ordering + duplicate merge — 88 records, 1,000 sessions | 13.0–15.6 ms | **0.12 ms** | **~113–130×** |
| `Fmt.grouped` — 50,000 calls | 745 ms | **20.0 ms** | **~37×** |
| Project-file search — 20,000 files, per body | 53.2 ms (3 scans) | **17.4 ms** (1 scan) | **~3.1× less work** |
| `FileChangeGroup.grouped` — 2,000 changes | 0.59 ms | 0.41 ms | unchanged within noise |
| Message ordering — 300 messages | 0.015 ms | 0.007 ms | unchanged within noise |
| New: `UsageSeries.bucketed` — 365 → 120 bars | — | 1.58 ms | new capability |

Because the baseline chart called the series builder multiple times per body,
the effective per-render reduction is larger than the per-build number: a 1Y
Usage body could spend roughly 80 ms in series building before; it now performs
one build (2.2 ms) plus one bucketing pass (1.6 ms). For `All`, the baseline
could reach roughly 180 ms; it is now about 6 ms.

These are microbenchmarks, not UI frame measurements. They deliberately isolate
the pure work that was repeated by SwiftUI bodies; the real app also benefits
from the removed duplicate requests, throttling and `Equatable` card reuse,
which are not captured in this table.

## Validation

```sh
swift build          # macOS: Build complete
swift test           # 42 tests, 0 failures
make mobile-build    # iOS simulator: ** BUILD SUCCEEDED **
Scripts/perf-benchmark.sh
```

New tests cover the extracted project ordering/merging and series bucketing:

- `ProjectOrderingTests` — running counts, duplicate canonical merge, ordering
  precedence, running-by-project ordering.
- `UsageSeriesTests` — bucket sums/counts and the “short series unchanged” case.

Behavior worth knowing when reviewing:

- The Live tab and Projects list now show a first page and a **Show more**
  control; the underlying fetched page is still 60 sessions.
- `Load earlier` pages automatically when the sentinel becomes visible.
- Charts over 120 points are bucketed, so the x axis represents a bucket
  (typically a few days) rather than one day.
- Caches evict after 16 entries; the open session/project is pinned.
- Skeletons do not animate when Reduce Motion is enabled.

## Remaining opportunities

These were intentionally left out of this pass:

1. **Split the observable stores by screen.** `AppState`/`MobileStore` publish
   every poll to every observing view. Cached derived data removes the
   expensive work, but SwiftUI still re-evaluates bodies every five seconds.
   Per-screen observable slices (or the Observation framework) would remove
   that identity churn.
2. **Cache chart series by range in the store.** The views now build each
   series once; a store-level cache would also remove the remaining per-render
   work when returning to the Usage tab.
3. **Incremental message updates.** *Done on iOS (2026-10-23):* the detail view
   now renders cached messages and asks the hub for `message?since=<newest>`.
   The Mac detail view still refetches its newest window.
4. **Server-side activity snapshots and bulk stats.** This would remove the
   first-render seeding lag and make project totals cheaper to show inline
   (already noted in `NOTES.md`).
5. **Virtualize very large diffs and file lists further.** `LazyVStack` limits
   row construction, but a 20,000-file search still scans the array; a small
   indexed search structure would make typing cheaper on very large work trees.
6. **Add Instruments/UI-test benchmarks in CI.** The current benchmark guards
   the shared algorithms; it does not measure launch time or scroll hitch rate.
7. **Retention policy for the hub's message cache.** Long-running installs still
   grow the SQLite database (a server-side follow-up from `NOTES.md`).

## Changed files

- Shared models/formatting: `Models/Models.swift`, `Models/UsageSeries.swift`,
  new `Models/ProjectOrdering.swift`, `Support/Formatters.swift`.
- Shared views: new `Views/PerformanceViews.swift`; `Views/ChangeViews.swift`,
  `Views/LiveTab.swift`, `Views/PanelView.swift`,
  `Views/ProjectDetailView.swift`, `Views/ProjectFilesView.swift`,
  `Views/ProjectsTab.swift`, `Views/SessionDetailView.swift`,
  `Views/UsageCharts.swift`, `Views/UsageTab.swift`.
- macOS state: `AppState.swift`.
- iOS state/views: `MobileStore.swift`, `OpenCodeBarMobileApp.swift`,
  `LiveView.swift`, `ProjectsView.swift`, `ProjectDetailView.swift`,
  `UsageView.swift`, `SessionDetailView.swift`, `MobileCharts.swift`,
  `MobileChangeViews.swift`, `MobileMessageViews.swift`,
  `MobileProjectFiles.swift`.
- Project and tooling: `project.yml` (shared skeleton file),
  `Scripts/perf-benchmark.sh`, `Scripts/PerfBenchmark.swift`,
  `Tests/OpenCodeBarTests/ProjectOrderingTests.swift`.
- Documentation: `performance/README.md`, `performance/before.md`,
  `performance/after.md`.
