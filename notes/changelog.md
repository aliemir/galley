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
