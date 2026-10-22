# Baseline performance analysis

**Date:** 2026-10-22
**Scope:** macOS menu bar app (`Sources/OpenCodeBar`) and iOS/iPadOS app
(`Sources/OpenCodeBarMobile`), including the shared model, formatting and view
code they compile.
**Status:** captured before the performance changes.

## Method

1. Read the polling/event pipeline, the shared stores (`AppState`,
   `MobileStore`), and every screen that renders a list, chart, diff or
   conversation.
2. Identify work that is repeated per body evaluation, per row, per poll or per
   event.
3. Measure the pure, shared hot paths with a synthetic benchmark
   (`Scripts/perf-benchmark.sh`). The data set models a heavy but realistic
   history:
   - 1,000 sessions over 365 days across 80 projects (plus duplicate project
     records), 20 active sessions;
   - 365 days of activity in `Stats`;
   - 2,000 file changes with 40-line patches;
   - 20,000 project files;
   - 300 conversation messages.
4. Compare with a clean macOS build (`swift build`), the unit tests
   (`swift test`) and an iOS simulator build (`make mobile-build`).

Environment: Apple Swift 6.4, macOS arm64, Xcode 27.1. The benchmark is compiled
with `swiftc -O`. Numbers are per operation on one machine and include ordinary
run-to-run variance; they are useful for relative comparisons, not as absolute
budgets.

## Measured hot paths

| Path | Baseline |
| --- | ---: |
| `UsageSeries.build` — 1,000 sessions, 365 days, `1Y` | **20.7 ms/op** |
| `UsageSeries.build` — same data, `All` | **46.1 ms/op** |
| Project ordering and duplicate merge — 88 records, 1,000 sessions | **15.6 ms/op** |
| `Fmt.grouped` — 50,000 calls | **745 ms** |
| `FileChangeGroup.grouped` — 2,000 changes | 0.59 ms/op |
| Project-file search — 20,000 files, one scan | 37.8 ms cold / 17.5 ms warm |
| Message ordering — 300 messages | 0.015 ms/op |

The important part is not the single-call cost but how often the UI paid it.

## Findings

### 1. Project ordering was quadratic in practice — high

`AppState.orderedProjects` and `MobileStore.orderedProjects` merged duplicate
records and sorted them with a comparison closure that called
`runningSessions(in:)`. That helper filtered **all sessions** and sorted the
result for every pair of projects the sort compared. With `P` projects and `S`
sessions the effective cost was `O(P × S log P)`.

The lists are small in the common case, but the property is read by:

- the Projects tab;
- the Live tab's project filter (which also scanned `recent.contains` per
  project);
- every re-render, including the 5-second poll.

At the measured 15.6 ms per evaluation this is enough to produce a visible hitch
when the Projects tab or the project filter is open.

### 2. Derived feeds were recomputed on every read — high

`runningSessions`, `recentSessions`, `activeSubagentCount(for:)`,
`runningSessions(in:)` and `projectName(for:)` were computed properties or
linear scans. Each view body that touched them repeated the filter/sort or scan.
A single row could trigger `activeSubagentCount` over every session, and the
Live and Projects tabs touched several of these per row.

### 3. Usage charts rebuilt the whole series several times per body — high

`UsageTrendCard` (both apps) exposed `points` as a computed property. The iOS
body used it for the chart, the day count, total, average and peak; the macOS
body computed it once for the chart and again in `hasData`. That is up to four
full series builds per body.

Each build formatted a day string per activity entry, per session and per day,
and — for `All` — walked the complete history day by day. Because both stores
are `ObservableObject`s that publish on every poll, the Usage screen re-rendered
every five seconds even while the user was reading it. A 1Y chart could spend
roughly 80 ms rebuilding data for a frame that had not changed.

There was also no down-sampling: an `All` range produced one bar per day, which
is both expensive and visually sub-pixel beyond a year.

### 4. `Fmt.grouped` allocated a formatter per call — medium

`Fmt.grouped(_:)` constructed a new `NumberFormatter` for every call. It is used
for stat tiles, tool counts, model rows, chart labels and project totals. The
measured cost was about 15 µs per call (745 ms for 50,000 calls). A dense Usage
screen calls it dozens of times per render.

### 5. File-change grouping and patch parsing were repeated per row — medium

`SessionChangesView` exposed `groups` as a computed property. The body read it
for the `ForEach` and then read `groups.count` again inside the row builder, so
grouping was recomputed once per row (`O(n² log n)` for a large change list).
Each `FileChangeCard` also recomputed `change.patchLines` (splitting the patch
string) multiple times per body.

### 6. Loading states were spinners, not layouts — medium (perceived)

Screens showed `ProgressView` plus a label while data arrived. The real content
then replaced it, changing the panel height and scroll position. On the Mac
panel this is especially noticeable because the popover is a fixed 400 × 626
surface, and on iOS it makes the first paint feel slower than it is.

There was no skeleton treatment for conversation, stats, changes, subagents,
projects, project detail or usage.

### 7. Lists were eager and pagination stopped at the data boundary — medium

- The conversation rendered every loaded message; on iOS the screen itself used
  an eager `VStack`. Only the outer panel used a `LazyVStack`, and the
  conversation was a single child of it, so individual message rows were still
  built eagerly.
- The Live tab sliced recent sessions to 20 (macOS) / 30 (iOS) with no way to
  reveal more, even though 60 were already in memory.
- The Projects tab rendered every project and project detail rendered up to 20 /
  40 sessions eagerly.
- `ProjectFilesView` read its `visible` computed property three times per body
  (empty check, count and list), scanning up to 20,000 paths each time.
- "Load earlier" required an explicit click; there was no infinite-scroll
  sentinel.

### 8. Polling and event handling did redundant work — high

- The 5-second poll assigned fresh arrays to `@Published` properties even when
  the content was unchanged, invalidating every observing view.
- `SessionDetailView` re-fetched 100 messages on every `session.updated` change,
  including while the Stats or Changes tabs were open. It also re-sorted the
  full loaded window each time.
- `scheduleLiveRefresh` cancelled and recreated its 400 ms debounce task on every
  event. A busy event stream could keep postponing the refresh indefinitely.
- Missing active sessions were fetched serially in a `for` loop.
- `refreshAll` awaited live, stats, history and usage one after another.
- `PanelView.task` on macOS and `UsageView.task` on iOS issued requests that the
  bootstrap path had already made.
- On iOS, polling and the event stream kept running while the app was in the
  background.

### 9. On-demand caches grew without bound — medium (long sessions)

`projectDetails`, `sessionChanges`, `projectChanges`, `projectFiles`,
`sessionStats` and `subagentLists` kept every entry for the process lifetime.
Opening many sessions or projects kept their messages, patches and file lists
resident.

### 10. Message rows were never considered equal — medium (streaming)

`SessionMessage` and `MessagePart` were not `Equatable`, and `MessageCard` had no
identity for SwiftUI diffing. Every parent update re-evaluated the body of every
message card and every part, which matters most during streaming when usage and
activity events arrive continuously.

## What the numbers meant in practice

- **Projects/Live:** ~15 ms per project-list evaluation, multiplied by the
  filter menu's `recent.contains` scan and by every 5-second re-render.
- **Usage:** up to ~80 ms of series building per body on a one-year window, plus
  formatter allocations in the tiles.
- **Project detail / Files:** ~53 ms per body when a query was active, because
  the same 20k-path scan ran three times.
- **Session detail:** a 100-message fetch and full re-sort every time the
  session's `updated` timestamp moved, even on tabs that do not show messages.

These are the paths targeted in [after.md](after.md).
