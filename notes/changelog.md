# Changelog

A running log of what was done on this app, newest first. Not the App Store
"What's New" — that lives in `store-metadata/listing.json`. This is the record
an agent reads to find out where the last session left off.

One entry per meaningful step, written as it happens rather than reconstructed
at the end, and kept in step with the git history. Idea and design *reasoning*
belongs in `notes/decisions.md`; this file is what changed.

Format:

```md
## 2026-09-01

- Added the onboarding flow and its three screenshots (`feat(app): …`, `a1b2c3d`)
- Pushed the en-US and tr listing to ASC; keywords at 98/100 chars
- Build 12 uploaded → processing → released to the internal group
```

Worth an entry: shipped features, pivots, releases and build numbers, ASC
changes (listing, IAP, tester groups), anything a future session would
otherwise have to re-derive. Not worth one: typo fixes and formatting.

<!-- newest entries go directly below this line -->

## 2026-11-01

- ⌘K is names only again; text matches show there only when no file name
  matches, labelled "No file names match — in the text" (before, they always
  followed the names, and with no names they looked like ⇧⌘F)
- Palette results carry their workspace's icon (with more than one
  workspace) instead of its name in the path; the list is sized to its rows'
  measured height, so no empty band under the last result
- Palette: "#" switches to sections and leaves the field (the icon shows it;
  Backspace in an empty field goes back); rows are identified by their
  result only, which fixes a stale, clipped row when results changed kind
- Highlights snap to whole words without crossing into the next block: a
  drag to the end of the front matter no longer took the heading's first
  word with it (which put the note under the heading); a note on the front
  matter sits under the whole block, not inside its grid
- Contents and Files lists end with 32 pt of space, so the last row can be
  scrolled clear of the window's bottom edge; the workspace list gets a little
- Tidied names are title case: "Auth Migration Plan", with short words
  ("of", "the", "to"…) lowercase inside a title, acronyms as before
- Your marks are purple everywhere: highlights and note cards on the page
  match the feedback colour of the chrome, so they no longer look like the
  agent's changes (amber). Notes are a bubble pointing at their passage, not
  a barred box. The document's own `==marks==` stay yellow. The current
  section in Contents lost its left bar (the row's shade already says it)
- Welcome screen copy rewritten: "Read what your agents write.", the three
  things Galley does, and feedback among the hints
- Single Markdown files open on their own — Finder's Open With, a
  double-click (once Galley is the default), the Dock icon, ⌘O (now "Open…",
  folders or files), a drop on the window. A file inside a workspace opens
  there; any other joins **Opened Files**, a workspace of files opened one at
  a time (own bookmarks, polled for changes since there is no folder to
  watch), with read state, change marks, highlights and feedback like any
  other. Each opens in a tab. "Add Its Folder as a Workspace…" and "Remove
  from Opened Files" on the file. Document types in `app/Info.plist`
- Tabs in the page column, Safari's way: a click opens in the current tab,
  ⌘-click (files, links), "Open in New Tab", ⌘Return in the palette or ⌘T
  open a new one; ⌃Tab / ⌃⇧Tab step, ⌘W closes (the window when it is the
  last), ⌥⌘W closes the others. A file has at most one tab — going to it goes
  to its tab. The bar only shows from two tabs; back tabs show a dot when an
  agent rewrites their file; drag to reorder, drop a file to open it. Tabs
  are restored on relaunch
- Workspaces show as the icon rail by default (names: ⌥⌘4, drag the edge, or Settings)
- Full-text search: ⇧⌘F searches every file's text (all words, at word
  starts, case and accents ignored) with snippets; ⌘K shows text matches
  under the name matches; Tab switches; choosing one opens the file with
  the match found
- The palette, panel button and drop highlight now follow the theme (they
  were always light)
- Feedback indicators are purple (badges, dots, copy buttons); rail dots
  grow into counts on hover; workspace badges no longer clip; swipe dead
  zone 40 pt
- Small sideways swipes (under 28 pt) no longer move panels
- Badges show new, changed and feedback separately with counts (workspace
  rows, rail dots, Files header); files get a feedback dot that grows into
  a count on hover
- Copy-feedback buttons for the file and the workspace in the page's top
  strip, each with a chevron menu to clear
- Feedback: a note on any highlight ("Add Note" on the selection pill, ⌃⌘N,
  or on a highlight), shown as a card under its passage and in Contents;
  Copy Feedback (⇧⌘C, or for the workspace) for pasting to an agent; Clear
  Feedback for a document or workspace. Highlights snap to whole words
- Pinned files reorder by dragging, and any file dragged onto the Pinned section (or the Files header) is pinned there
- Default swipe order is Files → Contents → Workspaces; installs still on the old default move to it once
- Files can be pinned (context menu, ⌥⌘P): a Pinned section heads the Files column
- Workspaces reorder by dragging, in the list and the rail
- Workspaces have a colour (ten swatches or automatic) that tints their icon and rail ring
- Dragging the Workspaces edge narrower than 105 pt folds it into the icon
  rail, and dragging the rail wider than 130 pt opens the list again
- Columns toggle independently: ⌘1 Workspaces, ⌘2 Files, ⌘3 Contents (View
  menu too), ⌘\ hides all; swipes and ⌘] / ⌘[ follow the reader's order
- Column order now sets only the reveal order; columns keep their places on screen
- Type-to-select in the Files column: typing jumps a highlight to the
  matching file (prefix, then word start; a repeated letter cycles), Return
  opens it, Esc cancels; what was typed shows briefly at the column's foot
- Workspaces get their own name and icon (symbol, emoji or a tinted
  monogram) from "Name and Icon…" in their context menu — the folder is
  never renamed — and can show as a narrow rail of icons (⌥⌘4)
- Columns: the reader sets their swipe order in Settings (drag to reorder),
  can switch any off (Contents also with ⌥⌘2 or its header menu), and can
  drag a divider to resize one (double-click resets)
- Folder and workspace names are tidied like file names
- The page hides its scrollbar while panels slide; nothing else about the slide changes
- Reverted the frozen-width panel motion (horizontal scrollbar, content
  shifts); panels resize the page live again — see `decisions.md`
- Pull to next/previous now needs 220 pt of pull (was 150 — felt too short)
- Pull-to-next/previous rebuilt from the user's screen recording: the page
  draws its own stretch, so the ring, the page movement and the cue are one
  value; the bottom "Next" block is gone and appears only while pulling;
  cues no longer linger after a pull is abandoned; haptic tick at the
  threshold
- Trackpad gestures lock to one axis: a sideways swipe no longer nudges the
  page, and a slanted scroll no longer turns into a swipe
- Pull past the top goes back to the previous document, landing at its end
- Highlighting no longer re-wraps a paragraph: `box-decoration-break: clone`
  was switching off `text-wrap: pretty` (measured with the new `js` debug
  command); inline code paragraphs get balanced wrapping as a bonus
- Real-screen pass (Screen Recording granted): captured the window, the
  Appearance popover and both Settings tabs. Fixed the popover overflowing
  its edge and misaligned rows, the Settings window's empty third, and a
  swipe bug where a revealing column stayed hidden until release
- Debug automation can now open the popover and Settings and inject phased
  trackpad swipes and pulls; `tools/window-bounds.swift` finds window ids
- Second review pass (independent read of the whole app): 15 defects fixed —
  overlapping highlights, find offsets, exact-position restore, baseline
  scans, wikilink crashes, `$$` edge cases, safe link handling, sandboxed
  file drops, settings observers, tolerant library decoding (`d54193d`);
  app-scoped bookmark entitlement for relaunch (`cc0c86c`).
- Printing (⌘P) as ink on white (`10822dd`); 4,000-line render guard test.
- Personal highlights: a pill over any selection (or ⌃⌘H), stored by the app
  and anchored by text plus context; survive rewrites, short ones need
  context; orphans stay listed in the outline column (`feat(app): …highlights`).
- Go to File (⌘K) and Go to Section (⇧⌘K) palette with fuzzy matching (`9ff55eb`).
- Placeholder app icon drawn by `tools/make-icon.swift` (`51fe155`).
- First review pass: read-marking rules on quit, gesture momentum, file list
  keyboard focus, raw-HTML images, deleted files, narrow windows, window
  dragging (`982be92`).
- The reader itself: column stack with interactive swipes, WebKit page,
  six themes and six typefaces, change marks, folding, pull-to-next, find,
  state restoration, keyboard map (`04b3ca1`, `656904e`).
- Document layer: swift-markdown renderer with GFM, callouts, KaTeX, Mermaid,
  footnotes, emoji, wikilinks, front matter; block diff; pretty names (`be9ebde`).
- Vendored KaTeX, Mermaid, highlight.js and gemoji data (`6c3ae99`).
- Renamed the template to the placeholder name Galley (`936e95b`).

## 2026-10-31

- Recorded: leaning to direct download (Developer ID), reading experience
  first, agent integration later via a bundled CLI + skill.
- Retargeted the template from iOS to a native macOS app: macOS 26.0, App
  Sandbox with read-only user-selected files, hardened runtime, Mac icon sizes
  (`feat(app): retarget the Xcode project to macOS`, `f725783`). Builds and
  unit tests pass on `platform=macOS`.
- AGENTS.md, `check.sh` and `rename.sh` now describe a Mac app; the preflight
  checks the macOS SDK instead of an iPhone simulator (`0a6ea0f`).
- Release skill and store-media docs switched to the Mac App Store: `.pkg`
  upload, `APP_DESKTOP` screenshots at 2880 × 1800, window capture via
  `screencapture` (`de8aae1`).
- Recorded the macOS-only and sandbox decisions in `notes/decisions.md`;
  distribution channel left open.
