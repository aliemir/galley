# Idea: A printed copy of what your agent wrote

A minimal, read-only, typography-first Mac reader for the markdown files AI agents produce.
Think **Macaroni + Bear**: Macaroni's "what changed" awareness with Bear's calm layout and swipe navigation.

> It should feel like a printed copy of the file from your agent. You read it, mark it up with a highlighter, and notice the new pages on your desk. You never edit paper.

---

## Principles

- **Read-only.** The app never writes to a markdown file. It's paper.
- **Calm, not a dev tool.** Apple Notes / Bear feel. Opening it should not pull you into coding mode.
- **Taste over features.** Typography, margins and themes are the product.
- **Remembers everything.** Quit and reopen exactly where you left off.
- **Native.** SwiftUI + AppKit: real Mac menus, windows, keys and trackpad gestures.

---

## Core features (v1)

### Swipe stack navigation (Bear-style)
One axis of progressive reveal, toggled with swipes:

1. **Page**: focus mode, only the current file
2. **+ Outline**: table of contents for the current file
3. **+ Files**: files in the current workspace
4. **+ Workspaces**: all workspaces

- Trackpad swipes left/right step through the levels.
- Matching keyboard shortcuts (e.g. `⌘[` / `⌘]` to step, `⌘1–4` to jump to a level).

### Continuous reading
Like flipping through a stapled stack of paper:
- At the end of a document, a quiet footer shows what's next ("Next: *Auth migration plan*").
- Scrolling past the end needs a small extra pull with resistance, then it jumps to the next document. No accidental jumps while skimming.
- Documents stay distinct pages: a clear seam with the new title (and a "changed" badge if relevant).
- Crossing the seam marks the previous doc as read, switches the outline to the new doc, and restores its saved scroll position.
- "Next" follows folder order by default. Option: an unread/changed queue, to read everything the agent touched since you last looked as one continuous paper.

### Workspaces
- A workspace is a single folder (nested subfolders included).
- Multiple workspaces can be open at the same time.
- Switch between them from the outermost swipe level.

### Change tracking
- Live reload when an agent writes a file.
- "Changed since *I* last read it": the app keeps its own snapshot of each file's last-read version and diffs against it (FSEvents + snapshots, not git; agent output is often gitignored, uncommitted or outside a repo). Git can be an optional bonus.
- Highlight **additions and edits**; hide removals unless asked.
- Change bars in the margin, like a redlined contract.
- Changed/unread indicators at every level: workspace, file, outline section.
- A per-file "read" state, so unread and changed files look like fresh paper.

### Personal highlights
- Highlight text for yourself; nothing is written to the file.
- Stored in the app, anchored by **text plus surrounding context** (not line numbers), so highlights survive agent rewrites.
- If the highlighted text disappears, keep it as an "orphan" in a margin list instead of silently dropping it.

### Pretty file names
Display names instead of raw filenames:
- Drop the extension and leading dates or numbers (`2026-10-30_`, `03-`).
- Turn `-` and `_` into spaces, and split camelCase.
- Sentence or title case, keeping known acronyms (API, README, CLAUDE, PRD).
- Optionally use the file's first `# Heading` as its name.
- Show the real filename on hover or as a subtle subtitle.

### State restoration
Persist per workspace and per file: open file, scroll position, swipe level, folded/collapsed sections, highlights.

### Keyboard shortcuts for everything
Every action has a shortcut, and the shortcuts mirror the swipe model.

### Typography and themes
- Print-like reading: real margins, comfortable line length, good vertical rhythm.
- A few curated themes, Bear-style, rather than an endless theme editor.

---

## Maybe later
- Let agents read your highlights and comments:
  - a CLI bundled with the app, plus an agent skill for it, so the agent runs
    the CLI to pull "what the user highlighted / commented" (preferred over
    piping to `claude -p` — the app stays passive, agents come to it),
  - copy a selection as an agent-ready reference (`@path/file.md` + quoted text),
  - or a small MCP server exposing the same data.
- Optional git integration for history.
- Export highlights as notes.

## Out of scope
- Editing files
- Cloud sync, accounts
- Plugins, power-user configuration

## Business
- Free. Polish the landing page and onboarding as much as the app.

---

## Similar apps

### Readers / viewers
| App | Notes | Price |
|---|---|---|
| [Macaroni](https://macaroni.noodledragon.studio/) | Read-only, watches a folder, "What Changed" view. Closest to this idea. | Paid |
| [Marked](https://markedapp.com/) | Classic live-preview reader for any editor. | Paid |
| [MacMD Viewer](https://macmdviewer.com/) | Native viewer for AI agent output, Quick Look, Mermaid. | Paid |
| [MarkViewer](https://markviewer.com/) | Free, change detection with diff, AI review loop; little theming, has a built-in terminal. | Free |
| [QuickMD](https://github.com/b451c/quickmd) | Free, open source, native; best theming among free options (JSON themes, fonts). | Free |
| [MDViewer](https://masakai.github.io/mdviewer/) | Free, open source, notarized; light/dark only. | Free |
| [MDHero](https://mdhero.app/) | Free, open source, Tauri; reads Claude Code plans. | Free |
| [QLMarkdown](https://github.com/sbarex/QLMarkdown) | Quick Look extension with custom CSS themes. | Free |
| [Glow](https://github.com/charmbracelet/glow) | Terminal markdown renderer. | Free |

### Editors / writing apps (for inspiration)
| App | Notes | Price |
|---|---|---|
| [Bear](https://bear.app/) | The layout and swipe navigation reference. | Freemium |
| [Typora](https://typora.io/) | Seamless WYSIWYG markdown. | Paid |
| [iA Writer](https://ia.net/writer) | Typography-first writing. | Paid |
| [Obsidian](https://obsidian.md/) | Powerful, but an editor/PKM tool rather than a calm reader. | Free |
