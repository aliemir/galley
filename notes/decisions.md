# Decisions

What was chosen and why, with the options turned down. Each entry is dated;
a later one says when it replaces an earlier one.

## 2026-10-31 — Native macOS only

**Chosen:** a single macOS target (SwiftUI + AppKit), macOS 26.0 minimum (lowered to 15.0 on 2026-11-02, see below),
built with the macOS SDK. The repo started from an iOS app template, retargeted
to the Mac.

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

## 2026-10-31 — App Sandbox on, files read-only (sandbox superseded 2026-11-01)

**Chosen:** `ENABLE_APP_SANDBOX = YES`, `ENABLE_USER_SELECTED_FILES = readonly`,
hardened runtime on, category `public.app-category.productivity`.

**Why:** read-only is the product ("you never edit paper"), and the sandbox is
required for the Mac App Store. Productivity rather than Developer Tools
because the app is meant to feel calm, not like a dev tool.

**Consequence:** workspaces must be reopened through security-scoped bookmarks.

## 2026-11-01 — Distribution: free, on GitHub, no App Store, no sandbox

**Chosen:** Galley is free and open source, published on GitHub, with
releases downloaded from there: Developer ID signing, hardened runtime,
notarization, a DMG per release. No Mac App Store. The App Sandbox is off.

**Why:** the store adds nothing to a free app shipped from GitHub, and the
sandbox stood in the way of the features that make Galley more than a
viewer: a `galley` command an agent can run to read the reader's feedback
(another program cannot read a sandboxed app's data), installing that command
on the PATH the way VS Code installs `code`, and opening a single file or a
folder without a permission panel. VS Code, Cursor, Obsidian and most
developer tools on the Mac ship the same way.

**What stays locked down:** the reader page — scripts only from the app, no
network, no navigation, raw HTML cleaned (see below) — and the app never
writes to a Markdown file. "Read-only by design" replaces "sandboxed" in the
privacy story.

**Moving off the sandbox:** the first launch without it copies the library
(`library.json`, snapshots) and the settings out of the old container
(`~/Library/Containers/com.aliemir.galley`) — copied, not moved, so the old
copy remains if anything goes wrong.

**Rejected:** the Mac App Store (and with it the sandbox, a sandboxed CLI and
an app-group container to share data with it — all cost, no benefit for a free
GitHub release).

**Later:** an update mechanism (Sparkle, its feed on GitHub). The release
script came on 2026-11-02 (`tools/release.sh`).

## 2026-10-31 — Focus: reading experience first (the agent loop followed on 2026-11-01)

**Chosen:** the current phase is the reading experience and ease of use —
typography, navigation, change tracking, highlights, state restoration.
Agent integration is out of scope for now; do not build hooks to agents yet.

**Later:** a small CLI that ships with the app, plus a skill for it, so
agents run the CLI to pull the reader's highlights and notes. The app stays
passive; agents come to it. (Built on 2026-11-01: the `galley` command.)

## 2026-10-31 — The name: Galley (settled 2026-11-02)

**Chosen:** *Galley*, bundle id `com.aliemir.galley`. A galley proof is the
printed copy of a text you read and mark up but never rewrite — the app's
whole premise. It began as a placeholder and is now the name, with the icon
`tools/make-icon.swift` draws: a sheet of paper with a change bar in its
margin.

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

## 2026-11-01 — Debug-only automation

Debug builds carry `DebugAutomation`, driven by `tools/galley-debug.swift`, so
development and the capture script can open fixture folders, drive the app
and snapshot the window. A debug copy on a throwaway library keeps its own
settings and home. Release builds have none of it.

## 2026-11-01 — Panels resize the page live; the text re-wraps as they move

**Chosen:** while columns slide in or out, the page simply gets narrower or
wider on every frame and the text re-wraps with it (the original behaviour).

**Rejected:** holding the text column at a fixed width for the duration of
the motion and re-wrapping once at the end, anchored to the line being
read. It was built and reverted the same day: the frozen column
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
Settings → General → Columns only drives swipes and ⌘] / ⌘[: a swipe right
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

**Rejected:** the preview tab first planned (single click reuses a
preview tab, double click keeps it, as in VS Code). Finder teaches people to
double-click files, and every double-click would have left a kept tab behind
— tabs piling up in a reader meant to be calm. Also rejected: native window
tabs (`NSWindow` tabbing), which would need a whole window — model, web
view, columns — per tab.

## 2026-11-01 — A file opened on its own joins "Opened Files"

**Chosen:** a Markdown file opened from outside every workspace goes into a
workspace of its own kind, *Opened Files* (`WorkspaceRecord.kind = "files"`),
which lists files opened one at a time, keyed by absolute path, each with its
own security-scoped bookmark. Everything a workspace has — read state,
change marks, highlights, feedback, pins, tabs, search — works for them
unchanged. Opening registers Galley as an *Alternate* viewer for Markdown: it
offers itself in Open With and never takes over the default unless the reader
sets it in Get Info.

**Why:** the sandbox grants the file, not its folder, so the old behaviour
(an open panel asking for the folder, then a whole workspace) put a prompt in
front of every double-click, and a folder like Downloads is not something
anyone wants watched. Promoting a file is still one step away ("Add Its
Folder as a Workspace…").

**Watching:** there is no folder Galley may watch, so the files' dates and
sizes are checked every 1.2 s (fresh `URL`s each time — a kept `URL` caches
its resource values, which hid every change in the first build).

**Rejected:** a tab that shows a file outside any workspace with no record
behind it (no highlights, no change tracking, nothing restored on relaunch);
one workspace per opened file (a rail full of single files).

## 2026-11-01 — One colour per source of marks

**Chosen:** blue is new, amber is what the agent changed, purple is what the
reader marked — highlights, notes, feedback counts and buttons alike. The
page's highlight is `Theme.highlight` (`--hl`), a wash of the chrome's
feedback purple; `Theme.mark` stays yellow for `==marked==` text, which is
the author's, not the reader's. Notes under a passage are a bubble with a
caret, never a box with a side bar: a bar is how the page marks a change and
how a callout begins.

**Why:** the highlighter's yellow and the change amber were a shade apart (in
Ink and Lamplight, the same value), so a highlighted passage read as a
change and a change read as a highlight.

**Rejected:** gold for feedback with a yellower change colour — any two warm
yellows stay too close to tell apart at a glance.

## 2026-11-01 — Settings as panes; shortcuts and icons are the reader's

**Chosen:** Settings is five toolbar panes (General, Reading, Themes,
Shortcuts, App Icon), after Bear's, instead of two crowded tabs. Themes are
a gallery of cards that show each theme rather than name it; the well-known
palettes (Solarized, Rosé Pine, Catppuccin, GitHub, Gruvbox, Nord, Dracula,
Tokyo Night) are mapped onto the reader's roles, so changes stay amber-ish
and the reader's marks purple-ish in every one.

**Shortcuts:** every menu action and the tab keys read from one registry
(`App/Shortcuts.swift`), so a change shows in menus and tooltips at once.
Taking a key another action had moves it (and says so) rather than refusing;
macOS's and editing's own keys and bare keys are refused. Rejected: leaving
it to System Settings → Keyboard → App Shortcuts, which few find and which
cannot reach keys handled outside the menus (⌃Tab).

**App icon:** variants are recolours drawn by the same script as the icon,
so the whole set regenerates whenever the icon is redrawn. The
choice sets the Dock icon while Galley runs; Finder keeps the standard icon
(Bear behaves the same).

## 2026-11-01 — The website reads like the guide

**Chosen:** the website looks like Galley's own page — the
guide's content and typography on the Paper theme — with GitHub and Download
buttons added. One look across app, guide and site.

## 2026-11-01 — The agent loop: one binary, and the app holds the pen

**Chosen:** `galley` is the app's own binary, run as a command when called
by that name (the symlink `galley install` makes) — no second target, and the
command shares the app's library and feedback code. It reads `library.json`
directly. Clearing writes, and the app keeps the whole library in memory and
saves it whole, so while Galley runs the command asks it to clear (a
distributed notification with the paths, answered with the counts) rather
than racing it; only when Galley is closed does the command edit the file.

Clearing is by path — a file, or every file under a folder — with
`--addressed` for passages no longer in the text. Clearing one highlight was
left out on purpose: an agent finishes a file, not a quote.

The skill tells agents to read with `galley feedback`, act on every item,
and clear only files they finished (`--addressed` when something is left).

## 2026-11-01 — The skill lives in `.agents`, linked for each agent

**Chosen:** one SKILL.md in `~/.agents/skills/galley` (or a project's
`.agents/skills/galley`), linked as `../../.agents/skills/galley` from
`.claude/skills` and, when Gemini CLI is installed, `.gemini/skills`. Codex
reads `.agents/skills` itself (Codex's docs); Claude Code reads only
`.claude/skills`; Cursor reads `.claude` and `.codex` skill folders too. The
same layout the reader's own skills and this repo's already use.

**Rejected:** `.claude/skills` alone (Claude Code only), or a copy per agent
(copies drift when the skill is updated).

## 2026-11-02 — macOS 15 Sequoia is the minimum

**Chosen:** `MACOSX_DEPLOYMENT_TARGET = 15.0` (was 26.0). Nothing in the app
needs macOS 26: it builds for 15 with no change. One version further back,
macOS 14 would need fallbacks for `WindowDragGesture`, `pointerStyle` and
`allowsWindowActivationEvents` (the title band and the column-resize
cursor) — not worth it until someone asks. Apple numbers by year since 2025,
so 15 is the version right before 26.

**What differs on 15:** WebKit there has no `text-wrap: pretty`, so
paragraphs break a little more plainly; nothing else is known. Test the
first release on macOS 15 (a virtual machine is enough) before shipping.

## 2026-11-02 — What a link to a file may do

**Chosen:** Markdown opens in Galley wherever it lives; a document opens in
its default app; anything that can run (apps, scripts — `public.script`
covers shell, Python, AppleScript — installers, disk images, workflows,
Shortcuts, `.inetloc`, or any file with the execute bit that is not a known
document) is only shown in Finder; HTML (it runs scripts in a browser) and
unknown types ask, offering Open or Show in Finder.

**Why:** the rule stays "a link in an agent's Markdown never starts code
with one click", but showing every file in Finder (the sandbox-era
behaviour) made a link to a screenshot or a PDF a detour.


## 2026-11-02 — Actions live in the ⌘K palette, not a palette of their own

**Chosen:** a third mode of the existing palette — `>` typed at the start, or
⇧⌘P to open it there — listing what the menus and the top bar do, under the
menus' names and with their shortcuts. Actions that would do nothing now are
left out, not greyed; themes and appearances only come up when a query asks.
The palette's own modes (Go to File, Search All Files, New Tab, Go to Section)
switch it in place instead of closing it.

**Why:** one place to type into, with the same keys (Tab, Backspace, arrows) as
`#` for sections. The menus stay the source of truth: an action runs the same
model call its menu item does.

**Rejected:** a separate command window (a second palette to learn); a
shortcut for the Appearance panel (it is all in Settings → Reading and Themes,
and the reader said it was not needed); listing every theme in the opening
list (nineteen rows of noise).

## 2026-11-02 — The repo holds the app and its site, nothing else

**Chosen:** remove the template scaffolding Galley never used — the server
Worker, the App Store pipeline and its media generator and metadata, the
preflight and rename scripts, and the skills and tools that served them.
Releases are DMGs on GitHub Releases, built by `tools/release.sh`; Sparkle
comes later.

**Why:** distribution is GitHub, not the App Store (see above), so the store
pipeline had nothing to do, and a public repo should not carry dead
scaffolding.

**Rejected:** keeping the scaffolding "ready" — it was never touched.

## 2026-11-02 — Changes can be read one at a time

**Chosen:** a tick beside each change bar (and ⌥⌘J for the change at the top
of the view) marks that run of changed blocks read. The file remembers the
ticked blocks by the hash of their text, on top of the last-read snapshot;
the last tick saves a new snapshot and clears them. Once a file is being
ticked, leaving it no longer marks it read.

**Why:** a long rewrite is reviewed piece by piece, like files in a pull
request. Remembering blocks by their text means a block the agent rewrites
again comes back as changed, with no bookkeeping of positions.

**Rejected:**
- *Rewriting the snapshot to take in each ticked block.* The snapshot is
  Markdown and the diff works on rendered blocks; splicing one into the
  other is fragile for tables, lists and code.
- *The tick on the bar itself.* The heading fold buttons sit right there;
  the tick has a column of its own further out, and is hidden in very
  narrow windows, where Mark as Read still works.

## 2026-11-02 — Feedback is a draft until the reader saves it

**Chosen:** new highlights and notes are drafts — dashed on the page and in
the Contents column — until **Save Feedback** (⌘S, the top bar's button
while drafts wait) saves every draft in the workspace, stamping when. A
changed note becomes a draft again. Drafts are on by default and can be
turned off in Settings → General, which makes every mark saved as it is
made. Highlights from before have no flag and count as saved. Drafts stay
in the library the whole time; saving only changes their state.

The command shows saved feedback only (`--drafts` for the rest), and
`clear` leaves drafts alone. `galley feedback --wait` exits after the next
save under a path, printing what it added; `--watch` prints each save as it
comes. A save is a highlight whose id and save time are new, read from
`library.json`, which the app writes at once on a save.

**Why:** a reader marking a long plan is not done after the first note, and
an agent acting on half a round wastes both their time. An explicit save
is the signal an agent can wait on, which is what makes "keep watching for
my feedback" work — and later, hooks that hand a saved round to an agent
with the next prompt.

**Rejected:**
- *"Submit" with a paper plane* (the first name): the reader preferred
  Save, which also takes the Mac's ⌘S.
- *Comparing save times with the clock* for `--wait`: the library keeps
  whole seconds, so a save in the same second as the command starts would
  be missed or doubled.
- *A distributed notification from the app* for `--wait`: lost when nothing
  is listening at that instant; the library file is always there to read.
- *Printing all saved feedback on each save*: an agent that has not cleared
  the last round would act on it twice.
