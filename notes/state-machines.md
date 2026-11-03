# Implicit state machines

A survey (2026-11-03) of the lifecycles and modes the code keeps in loose
Bools, optionals, sentinels, counters, timers and DOM classes rather than in
one explicit state. Only `CLI.FeedbackOptions.Mode` and
`DebugAutomation.ScrollPhase` are explicit enums; everything below is not.

Found by reading `App/`, `Workspace/`, `Document/`, `Appearance/`,
`Interface/`, `Reader/` and `reader.js` in full. Nothing was run. Bugs
marked **verified** were re-checked against the source by hand. The others
come from careful reading but have not been reproduced.

## Bugs these machines cause today

Ordered by how likely a reader is to hit them.

| # | Bug | Machine | Status |
|---|---|---|---|
| 1 | **Mark as Unread is undone** whenever the end of the page is on screen. `toggleRead` → `refreshPage(keepPosition:)` → JS `update()` → `report(true)` with `reachedEnd: footerVisible` → `current.reachedEnd = true` (AppModel `handle(.scroll)`), so `leaveCurrent` marks the file read again. The `.distantFuture` sentinel only guards the timer half. On a page short enough to show its end, Mark as Unread never survives leaving | Read intent (§3) | verified— **fixed** in `3e058e2` |
| 2 | **`pull-armed` sticks after a panel swipe that starts at a page edge.** `.began` arms the pull. The horizontal end path returns through `finishSwipe` before the pull clean-up runs. The next `.began` empties `pullEdges` without `armPull(false)`, so the page loses its rubber band until the next `show()`. Low impact: the next armed gesture at an edge clears it, so it sticks only at an edge with no next or previous file | Gesture (§6) | verified— **fixed** in `3ee4ba6` |
| 3 | **`pendingRestore` leaks between workspaces.** `selectWorkspace(B)` reads `pendingRestore ?? B.selectedFile`, so clicking B while A is still on its launch scan uses A's path. A later rescan of B (any agent write) runs `workspaceRescanned`, sees `pendingRestore` and jumps the page away from what the reader is reading. `activateTab` on an unscanned tab sets it the same way | Page phase (§1) | verified |
| 4 | **A stale animated `show` overwrites a newer page.** `show(d1,'up')` arms an uncancellable 150 ms timer. A `show(d2,'none')` or an `update(d')` inside that window renders first, then the timer renders d1. Swift's `current` is d2 and drops d1's scroll reports. Trigger: pull or Next, then a click within 150 ms | Page render (§2) | verified |
| 5 | **The palette opens in the wrong mode.** ⇧⌘K or ⇧⌘P while the palette is open set `quickOpenSeed`. The view's `@State` already read it, and `onAppear` (which clears it) has already run. The next ⌘K opens in Sections or Actions | Palette (§7) | from reading |
| 6 | **Closing a tab can quit the app.** `closeTab` sets `activeTabID = nil`, then `activateTab(neighbour)`. If the neighbour's file was deleted in the back, `activateTab` drops it and returns: the closed document stays on screen with no active tab, and the next ⌘W closes the window, which quits. `closeOtherTabs(id)` in the same case removes **every** tab | Tabs (§1) | verified |
| 7 | **A hidden find bar lights matches up again.** `refreshPage` schedules `Task { sleep 520ms; runFind }`, which nothing cancels. `hideFind` leaves `findQuery` set, so Escape inside that window still searches and stores a result | Find (§5) | verified— **fixed** in `e97ff60` |
| 8 | **An open note editor is lost on any re-render.** The editing state lives only in the DOM. `render()` and `clearHighlights()` destroy it on every disk change, Save Feedback, `feedback clear`, or a new highlight | Note editor (§4) | from reading |
| 9 | **The CLI drops a save after a failed read.** `waitForSaves` sets `modified = now` before `LibraryLocation.read()` succeeds. The comment says "the next look will have it", but the next look sees an unchanged mtime. The baseline is also read (`state`) before `modified` is taken, so a save that lands in between is never reported. Both are rare: writes are atomic, and the window is milliseconds | CLI wait (§8) | verified— **fixed** in `44f5066` |
| 10 | **The fence trackers disagree.** `collectFootnoteDefinitions` closes a fence on any same-character run of three or more (even shorter than the opener, or with an info string). A ```` block showing a ``` example plus a `[^x]:` line loses that line to a footnote. `firstHeading` has a third rule. Indented code and HTML blocks have no mode, so `$x$`, `[^1]` and `[[x]]` in them leak as `GALLEY…Z` tokens | Markdown lines (§9) | verified |
| 11 | **The baseline scan overwrites a snapshot the reader just made.** `apply` writes `readHash` only where it is nil but saves *every* baseline snapshot. Reading a file during a new workspace's first scan leaves its snapshot and `readHash` out of step. That only matters if the file also changed between the scan's read and the reader's: rare | Scan (§10) | verified, rare |
| 12 | **A test copy writes the reader's real settings.** `ReaderSettings.init` calls `SandboxMigration.defaults()` with `.standard`, not `Preferences.store`. Once the reader's own copy has migrated, the flag is already set and it returns at once: a breach of the rule, not a live bug | Migration (§12) | verified, latent |
| 13 | Find's count goes stale after an in-place update: JS re-searches, Swift is not told | Find (§5) | from reading |
| 14 | The panel-motion watchdog resets a column-edge drag longer than 1.5 s (`swipeProgress` stays 0), so the scrollbar returns mid-drag. A `.mayBegin` → `.cancelled` after a swipe re-runs `finishSwipe` and ends a running motion early | Panel motion (§11) | from reading |
| 15 | `feedback clear` while Galley is not running is a TOCTOU: the app launching between the check and the write keeps the old library in memory and writes the cleared highlights back | CLI (§8) | from reading |

## The machines

Sorted by how much an explicit model would help.

### 1. What the page shows, and the tabs — **make explicit**

`AppModel`: `selectedWorkspaceID`, `current: OpenDocument?`,
`pendingRestore: String?` (where `""` means "nothing remembered"), the active
tab's `fileID: String?` (nil means waiting), `activeTabID`, and
`Workspace.hasScanned` on another object.

**States:** none · waiting(ws, restore) · empty(ws) · showing(doc).

**Allowed but meaningless:**
- `pendingRestore` for a workspace that is not selected, or one already scanned.
- `selectedWorkspaceID`, `current.workspaceID` and the active tab's workspace all different.
- `activeTabID` not in `tabs`.

`leaveCurrent()` → `current = nil` → `syncActiveTab` is repeated by hand at
four sites. `open(_:transition:)` takes its workspace from the selection, so
callers must set the selection first. When `open(_:in:)` fails to read, the
three ids are left out of step.

**Shape:** `enum Page { none, waiting(ws, restore: String?), empty(ws), showing(OpenDocument) }`,
with the selected workspace derived from it, and one `transition(to:)`
owning `leaveCurrent`/`syncActiveTab`. `activateTab` returns
`.activated | .removed | .waiting`, and callers must handle it. Fixes bugs 3
and 6 by construction.

### 2. Page transition and render (reader.js `show` / `update` / `render`) — **make explicit**

The phases are idle → leaving (150 ms) → entering → settle (double rAF) →
idle (460 ms). They are encoded in the `#page.className` strings and two
`setTimeout`s that are never stored. The `generation` counter guards the
async enhancement only, not the transition. `configure()` restores an anchor
in an rAF with no generation check. Swift waits a hard-coded 520 ms before
searching after an animated show; that only works because the JS leave timer
is 150 ms.

**Shape:** a `{phase, token}` record. Every `show` and `update` cancels the
pending timers, and a timer whose token is stale does nothing. Fixes bug 4.

### 3. Read intent of the open document — **make explicit**

`OpenDocument.openedAt` (with `.distantFuture` as an opt-out sentinel),
`reachedEnd`, `changes`, `FileRecord.seenChanges`/`markedUnread`/`readHash`,
and the `markingRead: Bool?` override on `leaveCurrent`.

**States:** fresh · looked-at · kept-unread · ticking · read.

**Shape:** `enum ReadIntent { auto(openedAt), reachedEnd, keptUnread, ticking }`,
where a scroll report cannot leave `keptUnread`. Fixes bug 1.

The persisted half (§10b) is derived twice, in `Workspace.recomputeStatuses`
and in `AppModel.load`. A single computed `ReadState` would remove the
duplicate.

### 4. Note editor (reader.js) — **make explicit**

The editor state is spread over:
- the `pendingNote` global;
- the `.hl-note.editing` DOM class and its `<textarea>`;
- a closure-local `done`;
- an expected `setHighlights` echo from Swift.

**States:** none · pending (waiting for the echo of a new highlight) ·
editing · committing · showing.

If Swift's `setNote` returns early (unknown id, or unchanged after trimming),
no echo comes and the card freezes in committing. If the new highlight
returns as an orphan, `pendingNote` is never cleared.

**Shape:** `noteEditor = {id, draft, phase}` held in JS state, re-opened after
`renderNotes`, with committing cleared on any echo or a timeout. Fixes bug 8.

### 5. Find session — **maybe**

The Swift side has `isFindVisible`, `findQuery`, `findResult` (with
`(0, -1)` as "none"), `findFocusRequest` (a counter used as an event), and an
uncancellable delayed `Task`. The JS side has `findState.index` (−1 means
"start from the reading position").

The stale guard compares the query only, not the document or whether find is
still visible.

**Shape:** `FindSession { query, result, generation }` with one stored `Task`,
cancelled on hide and on page change. JS `update` reports `{count, index}`
back. Fixes bugs 7 and 13.

### 6. Trackpad gesture recognizer (`GestureMonitor`) — **make explicit**

Nine fields (`axis`, `held`, `fingerX`, `lock`, `pullEdges`, `pullEdge`,
`pull`, `wasReady`, `swallowMomentum`) plus the JS classes `pull-armed` and
`pulling`. The mouse-wheel pull is a second machine beside it (`wheelEdge`,
`wheelPull`, a 700 ms reset Task).

**States:** idle · undecided(held) · swiping · vertical(not armed | armed | pulling) · released · momentum(swallow).

A lost `.ended` (the app deactivated mid-gesture) leaves the page stretched or
a column half-revealed. The next `.began` resets the fields without undoing
their side effects.

**Shape:** `enum Gesture { … }` with one `exit()` that undoes side effects,
run before any `.began` that arrives in a non-idle state. Fixes bug 2 and the
second half of bug 14.

### 7. Quick Open mode — **make explicit (cheap)**

The mode is spread over:
- `quickOpenSeed` (string codes `""`, `"#"`, `">"`, read only by the view's `init`);
- `quickOpenSearchesText`;
- `quickOpenOpensTab`;
- the view's `@State scope`;
- `pageHasSelection`, filled by an async callback.

**Shape:** `enum PaletteMode { files(text: Bool, newTab: Bool), sections, actions }`
on the model, set by the commands and observed by the view. Fixes bug 5.

### 8. CLI ⇄ app over `library.json` — **make explicit**

`waitForSaves` keeps `known`, `modified` and `deadline`. The app writes the
whole file: debounced at 600 ms, flushed at once by Save and Clear.
`feedback clear` either asks the running app through a distributed
notification (with a 4 s timeout) or writes the file itself.

**Shape:** a small loop reducer: baseline (stat, then read) → observe(mtime)
→ read ok/failed, where `modified` advances only on success. Clearing needs
an "app owns the library" lock rather than a process-list check. Fixes bugs
9 and 15.

Related, and fine as it is: watcher presence (`Watchers/<pid>.json`, mtime
heartbeat, 15 s staleness). It is a clean, self-healing protocol.

### 9. Markdown line modes — **make explicit**

There are three independent fence trackers:
- `Preprocessor.process`: `fence: (Character, Int)?` and `display: (prefix, lines)?`;
- `collectFootnoteDefinitions`: `fence: Character?` plus a `current` continuation;
- `WorkspaceScanner.firstHeading`: `inFence: Bool`.

None of them has a mode for indented code or HTML blocks.

**Possible problems:**
- A fence opened inside a quote or list never closes at the container's end.
- An unclosed `$$` swallows the rest of the document.
- Front matter longer than 4 KB makes `firstHeading` read YAML comments as headings.

**Shape:** one `BlockLineClassifier` (normal · fence(char, len) ·
indentedCode · htmlBlock · displayMath) shared by all three passes. Fixes
bug 10.

### 10. Workspace scan and per-file read state — **make explicit (scan)**

**a. Scan.** Encoded by `scanTask` (cancel-and-replace), `needsBaseline`,
`hasScanned`, `isAvailable`, `hashes` (which doubles as the previous
generation), `watcher`/`pollTask`, the security scopes, and `close()`.

**States:** created · scanning · idle · closed. `rescan()` after `close()`
is unguarded.

Every FSEvents batch (0.3 s) cancels the scan in flight, so a large tree
under a constant stream of agent writes may never finish its first scan.

**Shape:** `idle | scanning | scanningDirty` (let the scan finish, then
rerun once) plus a lifecycle of `created / live / closed`. Fixes the
starvation risk and bug 11.

**b. Read state (persisted).** Encoded by `readHash`, `readAt`,
`markedUnread: Bool?`, `seenChanges`, and the snapshot file.

**States:** never-read · read · changed (partly ticked) · marked-unread.

- The snapshot is written at once but `readHash` only through the debounce, so a crash between the two leaves them out of step.
- `markRead`'s `alreadyRead` early return keeps stale `seenChanges`.

**Shape:** a computed `ReadState`, plus `readHash` flushed with the snapshot.
**Maybe.**

### 11. Panel motion — **maybe**

`panelMotions: Int` plus a watchdog `Task`, `swipeProgress`, and the column
divider's `startWidth: CGFloat?`. The count has no identity, so a late `end`
decrements a newer motion. A cancelled divider drag (its view removed)
leaves `startWidth` set.

**Shape:** `begin()` returns a token and `end(token)` removes it; the
divider uses `@GestureState`. Fixes bug 14.

### 12. Smaller ones

| Machine | Encoded by | Verdict |
|---|---|---|
| Highlight feedback draft → saved (read by app, CLI and agents) | `Highlight.draft: Bool?` and `sent: Date?`; `(true, date)` is representable | maybe: `enum FeedbackState { draft, saved(Date?) }` with Codable keeping the keys on disk |
| Bridge readiness (`ReaderController`) | `isReady` + `queued`. The async calls (`markChangeSeen`, `jumpToChange`…) bypass it and fail before ready. Transient commands (`setPull`, `armPull`) are replayed. Ready renders twice | maybe: `loading(queue) / ready / reloading(queue)` |
| Enhancement and `pendingScroll` (reader.js) | `generation`, `doc.pendingScroll` mutated on the payload, a shared `mermaidSeq`. Slow enhancement jumps the reader back to the opening anchor | maybe: skip the restore once the reader has scrolled |
| Page transition codes | `transition: String?` (nil means update; `"none"`, `"up"`, `"down"`) plus `keepPosition` and `landingAtEnd` | maybe: `enum PageChange { replace(Transition), refresh, diskUpdate }` |
| Drag flags | `draggedTab`, `draggedPin`, `draggedWorkspace`, cleared only on a matching drop | maybe: one `activeDrag`, cleared when the next drag starts |
| Sandbox migration | settings: a `migratedFromSandbox` flag with retry; library: "done" means `library.json` exists, with no retry when the source is unreadable | fix rather than model |
| `HTMLSanitizer.dropping` | per `clean` call, but cmark splits inline `<script>…</script>` into three nodes, so the content shows as escaped text | no |
| `WorkspaceRecord.kind: String?` (`"files"`) | changes what `path`, `documents` and file ids mean | maybe: a `Kind` enum |
| `LibraryState` | `activeTab: Int?` can be out of range; `selectedWorkspace` and `TabRecord.workspace` can dangle | validate in `init(from:)` |
| Change-mark leaving phase (reader.js) | CSS classes + a 260 ms timer; a resize during the timer rebuilds the tick button | no: exclude a `leaving` set |
| Workspace name/icon editor opened after a 0.4 s `asyncAfter` | uncancellable timer | no |
| `Shortcuts` overrides | `KeyShortcut("", [])` means unbound | no |
| Watcher polling, launch hand-off, confirmation flashes, shortcut recorder, type-select, scroll-report throttle, `FolderWatcher`, Opened Files poll | — | no: already contained |

## Bridge protocol notes

The Swift↔JS ordering assumptions worth keeping in mind for any of the
changes above:

1. Only `run` calls are queued before `ready`; the async calls fail silently until then.
2. `configure` precedes `show`.
3. An animated `show` renders 150 ms after the call.
4. Scroll reports carry the document id, and Swift drops any that are not for `current`.
5. Both `highlight`-with-`id` and `note` rely on a `setHighlights` echo.
6. `seen` is posted after JS has already removed the marks, with no rollback.

`next` is handled in Swift but never sent by `reader.js`, so it is a dead
message.

## Suggested order

1. Fix the four verified one-liners without new types:
   - `reachedEnd` cannot override Mark as Unread;
   - disarm the pull on the swipe path;
   - cancel the find Task on hide;
   - advance `modified` only after a good read, and stat before the baseline read.
2. `Page` enum plus `activateTab`'s result (bugs 3 and 6).
3. The JS transition token (bug 4) and the note-editor state (bug 8).
4. `PaletteMode` (bug 5).
5. The shared `BlockLineClassifier` (bug 10).
6. Scan coalescing and the baseline snapshot filter (bug 11).
