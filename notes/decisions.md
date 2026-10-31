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
