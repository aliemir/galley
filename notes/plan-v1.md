# Plan — v1: the reading experience

Focus (see `decisions.md`): reading and ease of use first; the agent loop —
notes on highlights, the `galley` command and its skill — came after.

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

## Navigation — columns

Columns sit in fixed places: **Workspaces · Files · Contents · Page**, and
each shows or hides on its own (⌘1 / ⌘2 / ⌘3, the View menu; ⌘\ for all).

- Two-finger horizontal swipe, **interactive** — the column follows the
  fingers and snaps on release (fingers right = reveal, left = hide). Which
  column comes next is the reader's order (Settings → General → Columns,
  drag to reorder; a column switched off there is passed over). The default
  order is Files, Contents, Workspaces.
- `⌘]` / `⌘[` do what a swipe does.
- Column widths are the reader's: drag a divider, double-click it for the
  default. Workspaces can be a rail of icons (⌥⌘4).

## Continuous reading

Nothing at the end of a page advertises the next one until you reach for it.
At the bottom, a *fresh* pull (not momentum from skimming) stretches the page
up with growing resistance and reveals "↓ Next · title" in the gap; its ring
fills with the same pull that moves the page, the trackpad ticks when it is
full, and letting go then slides the next document in. Letting go short
springs back and the cue fades at once; turning back into the text drops it
immediately. The same pull past the top goes back to the previous document
(folder order) and lands at its end. While a pull is armed, WebKit's own
bounce is switched off (`overscroll-behavior`) so only one stretch shows;
ordinary scrolling keeps the native bounce. Leaving a document after a real
look marks it read. Order: folder order, or the unread queue.

## Change tracking

Snapshot of each file as last read (app-owned, not git). Diff unit = leaf
block (paragraph, heading, list item paragraph, code block, table row).
Added blocks get a bar and a wash; modified blocks get a bar and word-level
`<ins>`. Removals hidden. Outline sections and files show dots. A new
workspace's existing files are the baseline — only what changes afterwards
lights up.

## Milestones

1. ✅ Package + renderer + web reader with themes and typography
2. ✅ Workspaces, file tree, pretty names, folder watching, persistence
3. ✅ Swipe column stack, outline with scroll-spy, keyboard map
4. ✅ Change tracking + read state + Unread feed
5. ✅ Continuous reading (pull to next, seam)
6. ✅ Find in page, Go to File / Go to Section, printing
7. ✅ Personal highlights (text + context anchors, orphans)
8. ✅ Section folding (page and outline share one fold state)
9. ✅ Feedback: notes on highlights, Copy Feedback for an agent, Clear Feedback
10. ✅ Full-text search (⇧⌘F; ⌘K falls back to it when no name matches; Tab switches)
11. ✅ Tabs in the page column (Safari-style; see `decisions.md`)
12. ✅ Single files: Open With, the Dock, ⌘O, drops → Opened Files
13. ✅ Settings as panes: themes gallery, typefaces, customizable shortcuts, icon colours
14. ✅ The agent loop: the `galley` command and its skill, Settings → Agents
15. ✅ The guide in the app, and the website (landing, privacy, support)
16. ✅ The palette's actions mode (`>` or ⇧⌘P)
17. ✅ Distribution: no sandbox, Developer ID, `tools/release.sh`

## Next

- **The first release** — a Developer ID Application certificate, then
  `tools/release.sh 1.0.0`; test it on macOS 15 first (a virtual machine is
  enough), and put the real repository in the website's GitHub links.
- **Updates** — Sparkle, with its feed published alongside each release.
- **Quick Look preview** — Space in Finder showing the page typeset.
  Deferred on purpose: it is a separate extension target (its own sandbox,
  WebKit's network entitlement, the renderer and web assets shared into it),
  and its use is browsing files in Finder, which double-click into Galley now
  covers. Worth it once the app is public: it puts the typography in front of
  people who have not opened Galley.
