# Changelog

A running log of what was done, newest first — the record an agent reads to
find out where the last session left off. One entry per meaningful step,
written as it happens and kept in step with the git history. The reasoning
behind a change belongs in `notes/decisions.md`; this file is what changed.
Typo fixes and formatting do not need an entry.

<!-- newest entries go directly below this line -->

## 2026-11-02

- Save Feedback shows a green dot while an agent waits on a folder holding one
  of the workspace's drafts (so saving reaches it), with
  `galley feedback --wait` or `--watch`, and its tooltip names the agent
  (from the processes above the command: Claude Code, Codex, Gemini CLI…).
  Each waiting command keeps a file in the library's `Watchers` folder,
  refreshed every 5 s and removed on exit; the app reads them every 3 s
- Site: Make it yours shows all nineteen themes as cards drawn in their own
  colours, as Settings → Themes does, instead of a screenshot of it;
  `tools/theme-cards.py` writes them from `Theme.swift`
- Site: the feature cards keep title and text at the top (a shorter card
  ends in space, not a lower title), and "Closes the loop" has a note-bubble
  icon with a highlighted line instead of a bar. Every card's icon has a
  tint of its own, lighter in dark mode
- Released Galley 1.1.1 (build 150): the Save Feedback button restyled. The
  first release to reach 1.1.0 through Sparkle; its feed verifies
- The Save button is drawn as the feedback buttons beside it — the purple
  wash, 26 pt, 7 pt corners, ink text — reading "Save Feedback", then "Saved"
- The site covers 1.1: ticking changes, drafts and Save Feedback (with a
  dashed draft mark in the text), `--watch` / `--wait` in the agents
  section, and ⌘S and ⌥⌘J in the keymap
- Released Galley 1.1.0 (build 144): drafts and Save Feedback, `--wait` and
  `--watch`, changes ticked one at a time, and Sparkle updates. The feed at
  `releases/latest/download/appcast.xml` verifies against the DMG
- The repo carries the `galley` skill as the app writes it, for agents
  working on Galley itself. `release.sh` adds the checksum to a copy of the
  release notes, not the file in the repo, and the feed's notes keep italics
- Galley updates itself with Sparkle 2: Galley → Check for Updates…, the
  palette, and Settings → General (a daily check, asked about first). The
  feed is `appcast.xml` on the newest GitHub release, written and signed by
  `tools/release.sh`. The README, site, privacy page and guide say the update
  check is the one request Galley makes
- The change tick grows into a "Mark as read" pill on hover, out into the
  margin (or to the right, when the page is near the window's edge)
- The Galley Guide, README and decisions cover ticking changes, drafts and
  Save Feedback, and `--wait` / `--watch`
- `galley feedback` shows saved feedback only (`--drafts` adds drafts,
  marked as such; JSON items carry `draft` and `saved`), and says on stderr
  when drafts are waiting. `--wait` blocks until the reader's next save
  under a path, prints what it added and exits (`--timeout`, status 2);
  `--watch` prints each save as it happens, for an agent's monitor. The
  skill teaches both, and to leave drafts alone
- Feedback starts as a draft: highlights and notes are dashed on the page
  (and in the Contents column's list) until the reader saves them with Save
  Feedback — the top bar's button while drafts wait, ⌘S, the Document menu
  or the palette — for the whole workspace. Editing a saved note makes it a
  draft again. Settings → General can turn drafts off. Highlights from
  before have no draft flag and count as saved. `galley feedback clear`
  leaves drafts alone unless given `--drafts`
- Changes can be read one at a time: a tick beside each change bar (shown
  while the pointer is on the change) takes its marks off, and Go → Mark
  Change as Read (⌥⌘J) ticks the change at the top of the view. A file
  whose changes are being ticked is not marked read just by leaving it; the
  last tick makes it read
- The repository is public at github.com/aliemir/galley (MIT), with a README
  that introduces Galley and explains building and signing it; the site's
  Download buttons serve the 1.0.0 DMG
- Released Galley 1.0.0 (build 131) on GitHub: signed with the Developer ID,
  notarized and stapled, `Galley.dmg` 12 MB; notes in
  `notes/release-notes/1.0.0.md`. The site is live at galley.aliemir.dev
- `tools/release.sh <version>`: bump, Release archive, Developer ID export,
  notarize and staple the app, a drag-to-Applications `Galley.dmg` signed,
  notarized and stapled, Gatekeeper check, tag, push and a GitHub Release;
  `--local` stops at a signed DMG. Needs a Developer ID Application
  certificate and `gh`
- Repo trimmed to the app and the site: the template's unused server, App
  Store pipeline and media, preflight and rename scripts, skills and tools
  are gone. AGENTS.md, README and `.env.example` describe Galley as it ships
- `galley feedback` and `feedback clear` match paths with symlinks resolved,
  so a workspace added through a symlink meets a command run from the real
  folder, and the other way round
- The palette covers the rest of the top bar and the columns' menus: Reveal
  Workspace in Finder, Sort Files by Folder / Recently Changed, Workspace Name
  and Icon…, and for an opened file Add Its Folder as a Workspace… and Remove
  from Opened Files; Set Up Agents… opens the top bar's panel while its button
  is shown. A query that spells out a word from its start ranks first
- Debug copies on a throwaway library keep their own settings
  (`Preferences.store`) and home (`GALLEY_HOME`), so scripted tests never
  touch the reader's
- The Clear Feedback alerts confirm with ⌘⌫, shown on the red Clear button
  ("Clear ⌘⌫"); Return does nothing there, so a stray one clears nothing,
  and Escape cancels
- The palette's actions include Find Next (⌘G) and Find Previous (⇧⌘G) once
  there is something to find on the page
- Fuzzy matching tries every starting place, so a query that names a whole
  word finds it rather than letters of an earlier one ("feedback" ranks Copy
  File Feedback first)
- The palette keeps the page's selection as it opens and puts it back as it
  closes (WebKit clears it when the field takes the keys), so its Highlight
  and Add Note work; both are listed only when there is a selection.
  Feedback actions say whose they are: Copy/Clear File Feedback, Copy/Clear
  Workspace Feedback, in the palette, the menus and the Contents menu
- Website: "Find anything" shows the palette's four modes as cut-outs
  (files, sections, text, actions), captured by `tools/capture-guide.sh`;
  a new "Keys for everything" section lists every default shortcut by menu
- The palette has an actions mode: `>` in ⌘K, or ⇧⌘P, lists everything in
  the menus and the top bar with its shortcut (themes and appearances once a
  query asks); actions that would do nothing are left out
- Settings → General can hide the Find and Appearance buttons at the top
  right; a hidden Find button still shows while the find bar is open
- Website lists the features as eight cards above the hero picture, a title
  and one line each (tracks changes, closes the loop, agent-ready, beautiful
  to read, remembers your place, all your projects, read-only and private,
  free and open source), each linking to its section; one column on phones
- Website pictures are sharp on Retina: full-resolution screenshots, each
  shown at no more than half its pixel width, and the two animations as
  H.264 videos (1600 px) instead of GIFs; the theme picture is smaller.
  `tools/record-window.swift` now records a window straight to a movie
  (ScreenCaptureKit), from which the capture script makes the guide's GIF
  and the site's MP4
- The agent skill shows `galley feedback --json` as data (path, items with
  text, note, section) and a `jq` line for picking out notes
- Links to files: Markdown opens in Galley wherever it is — this workspace,
  another (switching to it), or none (joining Opened Files), at the linked
  section; documents (images, PDF, text and code, media, office files) open
  in their default app; apps, scripts, installers, workflows and executables
  are only shown in Finder, with a note why; HTML and unknown types ask
  (`LinkTarget`)
- The minimum is macOS 15 Sequoia (was 26): nothing needed 26; it builds for
  15 unchanged. The website says so

## 2026-11-01

- The website (`website/`, not deployed yet): a landing page that reads like
  the guide — Paper theme, the reader's serif, Graphite when the system is
  dark — with the guide's pictures and GIFs, Galley's own change bar,
  highlight and note shown in its text, GitHub and Download buttons; plus a
  short, true privacy page (Galley collects nothing; Cloudflare and GitHub
  named for what they handle) and a support page with the common questions
- The agent skill lives in `.agents/skills/galley` — the shared convention,
  read by Codex — and is linked from `.claude/skills` (Claude Code, and Cursor
  reads it too) and `.gemini/skills` when those agents are installed; a
  project install writes `.agents` and links `.claude` relatively. The panel
  and `galley skill install` say which agents will find it
- The guide's pictures show four workspaces in the rail — three more small
  agent folders made by `tools/capture-guide.sh`, with their own icons and
  colours (debug `dress`) and a new file's blue dot
- The eye button for hidden comments is gone from the top strip; ⇧⌘H, the
  View menu and Settings remain
- Connecting agents has a home: a terminal button in the top strip (until
  the command and the skill are both installed, or "Don't show this button
  again") opens a panel — what the command does, Install for the command
  (admin prompt for /usr/local/bin) and the skill, copyable lines (what to
  tell the agent, the per-project skill, `galley skill print`). Settings →
  Agents keeps it for good, with Remove, and spots a link to another copy of
  Galley ("Point It Here") (`AgentSetup`)
- The guide, rewritten to cover everything: reading, columns and pulling (as
  GIFs), changes, marking up, handing back — Copy Feedback and the `galley`
  command with its skill — finding, tabs, single files, hidden comments (with
  a live one), themes, a key table, every syntax, and what keeps files safe.
  `tools/capture-guide.sh` now records the GIFs too (ffmpeg)
- Key symbols in running text (⇧⌘C) are drawn in the system face — reading
  faces lack them; code in table cells no longer breaks across lines
- Feedback says where each passage is: "Marked in Rollout › Token shape"
  (its headings, outermost first, without the document's own title), worked
  out when copied or read so it follows the file as it is now; in Copy
  Feedback and `galley feedback` (JSON: `section`)
- The `galley` command (`App/CLI.swift`): Galley's own binary, run as a
  command when called `galley` (or with `--cli`). `galley [path]` opens,
  `galley feedback [path] [--json]` prints the feedback on a file or folder,
  `galley feedback clear path … [--addressed]` clears it (a running Galley is
  asked to, by distributed notification, so the page updates; otherwise the
  library file is changed), `galley install [folder]` links it onto the PATH,
  `galley skill install [--global | --project | --dir]` writes the agent
  skill. Galley menu: Install Command Line Tool… (admin prompt for
  /usr/local/bin, like VS Code's `code`) and Install Agent Skill
- Raw HTML in Markdown is cleaned (`HTMLSanitizer`): GitHub's harmless tags
  stay, scripts/styles/frames/forms/SVG go with their content, and only safe
  attributes survive — no `style`, `class`, `id` or `on…`, so a file cannot
  hide text or fake a change mark or highlight; links and images only
  http(s), mailto, relative (and raster `data:` images)
- HTML comments are kept hidden; View → Show Hidden Comments (⇧⌘H), a
  Settings switch, and an eye button on pages that have some show them faint
  and labelled — what an agent reads, the reader can see
- The App Sandbox is off (free GitHub releases, see decisions): no
  entitlements files; the first launch copies the library, snapshots and
  settings out of the old sandbox container (`SandboxMigration`). Checked on
  the real library: 4 workspaces, tabs, 38 read records, snapshots, settings
- The Galley Guide ships inside the app (`app/Galley/Guide/`): what Galley
  does, with five screenshots, and a page that shows every syntax it renders.
  Opened from the welcome screen ("New here? Read the guide →") and Help →
  Galley Guide, like any single file. Pictures come from
  `tools/capture-guide.sh`, which runs a debug copy on a throwaway library
  (`-GalleyLibrary`) and a copy of the Showcase workspace
- The Dock icon carries the number of new and changed files across every
  workspace; Settings → General → "Show the number of files to read on the
  Dock icon" turns it off
- App Icon pane: the icon in ten palettes (Paper, Snow, Sepia, Lavender,
  Mint, Solarized, Graphite, Midnight, Rosé Pine, Nord), drawn by
  `tools/make-icon.swift --variants`; the pick is the Dock icon while Galley
  runs (Finder keeps the standard one)
- Every shortcut is the reader's own: Settings → Shortcuts lists all 40 by
  menu, with a filter; click one and press new keys (Esc cancels, Delete
  removes it). A shortcut taken from another action is moved and said so;
  macOS's and editing's own (⌘Q, ⌘C…) and bare keys are refused. Menus,
  tooltips, the Settings explanation and the tab keys all follow
  (`App/Shortcuts.swift`)
- Settings rebuilt as panes, Bear-style: General, Reading (typeface cards,
  size slider, spacing, width, Restore Defaults) and Themes — a gallery of
  cards, each a small page in its own colours (a change, a highlight, a
  link, a line of code). Thirteen well-known themes join Galley's six:
  Solarized Light/Dark, Rosé Pine and Dawn, Catppuccin Latte/Mocha, GitHub
  Light/Dark, Gruvbox Light/Dark, Nord, Dracula, Tokyo Night (palettes
  credited in Acknowledgements.txt). The Aa popover shows the themes for the
  appearance on screen, with "All Themes…"
- Palette sections: Backspace in an empty field now leaves them (the Mac's
  Backspace sends U+7F, which the `.delete` handler never saw), and Tab goes
  back to names rather than on to text
- The palette's "Tab: text" hint is a ⇥ keycap followed by where Tab goes
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
- Pull-to-next/previous rebuilt: the page
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
  file drops, settings observers, tolerant library decoding;
  app-scoped bookmark entitlement for relaunch.
- Printing (⌘P) as ink on white; 4,000-line render guard test.
- Personal highlights: a pill over any selection (or ⌃⌘H), stored by the app
  and anchored by text plus context; survive rewrites, short ones need
  context; orphans stay listed in the outline column.
- Go to File (⌘K) and Go to Section (⇧⌘K) palette with fuzzy matching.
- Placeholder app icon drawn by `tools/make-icon.swift`.
- First review pass: read-marking rules on quit, gesture momentum, file list
  keyboard focus, raw-HTML images, deleted files, narrow windows, window
  dragging.
- The reader itself: column stack with interactive swipes, WebKit page,
  six themes and six typefaces, change marks, folding, pull-to-next, find,
  state restoration, keyboard map.
- Document layer: swift-markdown renderer with GFM, callouts, KaTeX, Mermaid,
  footnotes, emoji, wikilinks, front matter; block diff; pretty names.
- Vendored KaTeX, Mermaid, highlight.js and gemoji data.
- Renamed the template to the placeholder name Galley.

## 2026-10-31

- Recorded: leaning to direct download (Developer ID), reading experience
  first, agent integration later via a bundled CLI + skill.
- Retargeted the template from iOS to a native macOS app: macOS 26.0, App
  Sandbox with read-only user-selected files, hardened runtime, Mac icon
  sizes. Builds and unit tests pass on `platform=macOS`.
- Recorded the macOS-only and sandbox decisions in `notes/decisions.md`;
  distribution channel left open.
