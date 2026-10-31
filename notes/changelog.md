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
