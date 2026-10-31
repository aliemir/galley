# Plan — v1: the reading experience

Focus (see `decisions.md`): reading and ease of use. No agent integration yet.

## Look

Native restraint as the baseline — system sidebar, white page, small grey
metadata, blue unread dots — with curated themes on top, and nothing that
reads as a dev tool (raw filenames, a separate code-style diff).
Changes are shown **in the rendered page**, as margin change bars and washed
insertions, not in a separate diff view.

## Architecture

| Layer | Choice | Why |
|---|---|---|
| Shell | SwiftUI + AppKit, one main window | Native chrome, real menus, Settings scene |
| Parsing | `swift-markdown` (Apple, cmark-gfm) in Swift | Swift owns the document: outline, diff units, pretty titles — all unit-testable |
| Rendering | One persistent `WKWebView`; Swift sends HTML fragments over a JS bridge | CoreText-quality text with CSS typography (hyphenation, `text-wrap: pretty`, hanging punctuation, tables), native selection, no reloads between documents |
| Code | highlight.js, bundled, no network | Agent output is full of code blocks |
| Files | security-scoped bookmarks + FSEvents | Works sandboxed or not |
| State | JSON in Application Support, settings in `UserDefaults` | Small, inspectable |

## Navigation — one axis

Columns, left to right: **Workspaces · Files · Outline · Page**. Level 1 is the
page alone; each step right reveals the next column to the left.

- Two-finger horizontal swipe, **interactive** — the column follows the
  fingers and snaps on release (fingers right = reveal, left = hide).
- `⌘[` / `⌘]` step, `⌘1`–`⌘4` jump.

## Continuous reading

Footer "Next: *title*". At the bottom, a fresh downward pull (not momentum from
skimming) fills a ring; release past the threshold slides the next document up
in place. Leaving a document after a real look marks it read. Order: folder
order, or the unread queue.

## Change tracking

Snapshot of each file as last read (app-owned, not git). Diff unit = leaf
block (paragraph, heading, list item paragraph, code block, table row).
Added blocks get a bar and a wash; modified blocks get a bar and word-level
`<ins>`. Removals hidden. Outline sections and files show dots. A new
workspace's existing files are the baseline — only what changes afterwards
lights up.

## Milestones

1. Package + renderer + web reader with themes and typography
2. Workspaces, file tree, pretty names, folder watching, persistence
3. Swipe column stack, outline with scroll-spy, keyboard map
4. Change tracking + read state + "Changed" feed
5. Continuous reading (pull to next, seam)
6. Find in page, quick open — if time allows
7. Personal highlights (text + context anchors, orphans)

Tabs: deferred — single window with per-workspace state first; native window
tabs later.
