# Decisions

What was chosen and why, with the options turned down. Newest first.

## 2026-10-31 — Native macOS only

**Chosen:** a single macOS target (SwiftUI + AppKit), macOS 26.0 minimum,
built with the macOS SDK. The repo started from the iOS app template; the
Xcode project, preflight, release skill and store-media docs were retargeted.

**Why:** the idea is a Mac reader for files agents write on that same Mac —
folder watching (FSEvents), trackpad swipes, multiple windows, keyboard-first.
None of it has an iPhone shape, and a native Mac feel rules out anything
cross-platform.

**Rejected:**
- *Multiplatform SwiftUI target (iOS + macOS).* Doubles the UI work for a
  device where agent output is not on disk, and pulls the design toward the
  lowest common denominator.
- *Mac Catalyst.* It would not feel like a Mac app, which the idea depends on.
- *Deployment target 27.0* (the current SDK). 26.0 keeps last year's Macs
  without giving up the current SwiftUI/AppKit design language.

## 2026-10-31 — App Sandbox on, files read-only

**Chosen:** `ENABLE_APP_SANDBOX = YES`, `ENABLE_USER_SELECTED_FILES = readonly`,
hardened runtime on, category `public.app-category.productivity`.

**Why:** read-only is the product ("you never edit paper"), and the sandbox is
required for the Mac App Store. Productivity rather than Developer Tools
because the app is meant to feel calm, not like a dev tool.

**Consequence:** workspaces must be reopened through security-scoped bookmarks;
"pipe a highlight to `claude -p`" from *Maybe later* cannot spawn a process
from a sandboxed app and would need another shape (copy to clipboard, a URL
scheme, or an MCP server the agent connects to).

## Leaning — distribution channel: direct download

**Leaning (not final):** direct download — Developer ID signing + notarization —
rather than the Mac App Store. Said "probably" on 2026-10-31.

**Not yet acted on:** the project is still configured for the Mac App Store
(sandbox on, `testflight-release` skill uploads a `.pkg`). Revisit the sandbox
and write a Developer ID + `notarytool` release path when release work starts,
not before.

## 2026-10-31 — Focus: reading experience first

**Chosen:** the current phase is the reading experience and ease of use —
typography, navigation, change tracking, highlights, state restoration.
Agent integration is out of scope for now; do not build hooks to agents yet.

**Later, replacing "pipe to `claude -p`":** a small CLI that ships with the
app, plus a skill for it, so agents run the CLI to pull the user's highlights
and comments. The app stays passive; agents come to it.

## 2026-10-31 — Placeholder name: Galley

**Chosen (placeholder):** *Galley*, bundle id `com.aliemir.galley`. A galley
proof is the printed copy of a text you read and mark up but never rewrite —
the app's whole premise. The real name is still to be decided.

**Renaming later** is a find-and-replace of `Galley` / `galley` across the repo
plus `git mv` of `app/Galley*` — `rename.sh` is one-shot and has been deleted.
Changing the bundle id resets the sandbox container (saved workspaces, read
state, highlights), which costs nothing before the first release.

## 2026-11-01 — Rendering: Swift parses, WebKit draws

**Chosen:** `swift-markdown` (Apple) parses in Swift — outline, diff units,
titles and syntax extensions are Swift and unit-tested. One persistent
`WKWebView` draws the page from HTML fragments over a small hand-written JS
bridge.

**Why:** WebKit is the system's own CoreText text stack, so the page is
native text with CSS typography (hyphenation, `text-wrap: pretty`, hanging
punctuation, real tables) and native selection — none of which `NSTextView`
gives without weeks of custom layout. SwiftUI `Text` cannot select across
paragraphs at all.

**Rejected:** `NSTextView`/TextKit 2 (tables fall back to TextKit 1, block
backgrounds and callouts need custom drawing); SwiftUI views per block (no
cross-paragraph selection); a JS markdown parser (the document model would
live in JS, untestable from Swift).

## 2026-11-01 — Third-party JS: only where nothing native matches

The user prefers not to depend on JavaScript packages. Three are vendored
anyway because syntax parity with other readers was asked for and no native
option matches them: **Mermaid** (no native renderer exists), **KaTeX**
(SwiftMath is the native alternative — lower fidelity, a contained swap if
wanted), **highlight.js** (code colouring). All are pinned, bundled, offline,
run under a strict content security policy, and each is loaded only when a
document actually contains a diagram, math or code. The reader's own script
has no dependencies. `gemoji` is data only (shortcode → emoji JSON). Licenses
are bundled in `Reader/Web/vendor/Acknowledgements.txt`.

## 2026-11-01 — Outgoing-network entitlement, with a page that has no network

**Chosen:** `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES`
(`com.apple.security.network.client`).

**Why:** in a sandboxed app WebKit's helper processes do not start without
it — the reader page sat at 10% loading and never reached the `galley://`
scheme handler. The app itself makes no requests, and the page cannot either:
its content security policy is `default-src 'none'` with only `galley:` and
`data:` allowed, and remote images render as a link chip instead of loading.
The privacy policy can still say the app sends nothing anywhere.

## 2026-11-01 — Debug-only automation and entitlements

Debug builds carry `app/Galley-Debug.entitlements` (read `/`, write
`/private/tmp/galley-debug/`) and `DebugAutomation`, driven by
`tools/galley-debug.swift`. They exist so development and the store-media
script can open fixture folders without the open panel and snapshot the
window without Screen Recording permission. Release builds have neither.

## 2026-11-01 — Panels resize the page live; the text re-wraps as they move

**Chosen:** while columns slide in or out, the page simply gets narrower or
wider on every frame and the text re-wraps with it (the original behaviour).

**Rejected:** holding the text column at a fixed width for the duration of
the motion and re-wrapping once at the end, anchored to the line being
read. It was built (`3629be0`) and reverted the same day: the frozen column
overflowed narrow windows and showed a horizontal scrollbar, and the single
re-wrap at the end read as a content shift. The user preferred the live
re-wrap, scrollbar movement included.

What actually bothered the user was only the scrollbar popping up and moving
while the page's length changed under the slide, so the page now hides its
scrollbar (`scrollbar-width: none`) for the duration of the motion.

## 2026-11-01 — Columns toggle on their own; swipes follow the reader's order

**Chosen:** the panel state is the *set* of columns showing. Each column
keeps its fixed place (Workspaces · Files · Contents · page) and toggles on
its own — ⌘1 / ⌘2 / ⌘3, numbered by place, also in the View menu with
checkmarks; ⌘\ hides them all and brings the same set back. The order in
Settings → Reading → Columns only drives swipes and ⌘] / ⌘[: a swipe right
brings in the first hidden column in the order, a swipe left takes away the
last showing one. A column switched off there is passed over by swipes but
still has its shortcut. On narrow windows the columns latest in the order
step aside first.

**Rejected, in the order they were tried the same day:** a depth into the
order that also rearranged the columns (the order is "how we toggle
things", not a layout); then a depth with fixed places (showing Workspaces
forced every column before it in the order to show too).

Older libraries stored a 1-based level; it is read as a depth into the
default order the first time, then the set is stored instead.

## 2026-11-01 — Notes sit under their passage, not in the margin

**Chosen:** a note is a small card under the block its highlight ends in
(inside it, for a list item or a table cell), tinted like the highlight and
set in the interface face, so it reads as the reader's words. **Copy
Feedback** (⇧⌘C, or for the whole workspace) writes Markdown for an agent —
absolute path, each quoted passage, the note under it — leaving out
passages no longer in the text, since the agent has dealt with them.
**Clear Feedback** removes highlights and notes for a document or a
workspace, after asking.

**Rejected:** margin notes beside the text. At the reading measure the
margin is about 140 pt in a normal window and nothing at narrow widths;
cards would collide or vanish exactly where they are needed.

Highlights now snap to whole words and drop surrounding spaces, so a drag
that stops a letter short still marks the word.

## 2026-11-01 — Tabs work like Safari's, not like an editor's preview tab

**Chosen:** tabs inside the page column. A click (file list, palette, link,
pull to next) changes the current tab; a new tab is asked for — ⌘-click,
"Open in New Tab", ⌘Return in the palette, ⌘T, or dropping a file on the
bar. A file is open in at most one tab: going to it goes to that tab. The
bar is not drawn until there are two tabs, so someone who never asks for one
sees the page exactly as before.

**Rejected:** the preview tab planned in `plan-v1.md` (single click reuses a
preview tab, double click keeps it, as in VS Code). Finder teaches people to
double-click files, and every double-click would have left a kept tab behind
— tabs piling up in a reader meant to be calm. Also rejected: native window
tabs (`NSWindow` tabbing), which would need a whole window — model, web
view, columns — per tab.

