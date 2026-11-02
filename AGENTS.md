# AGENTS.md

Galley — a native macOS reader for the Markdown AI agents write — and its
website. Free, open source, distributed from GitHub Releases (Developer ID,
notarized), not the App Store.

## Layout

| Path | What |
|---|---|
| `app/` | The macOS app (native, Mac only — no iOS target). `app/Galley.xcodeproj` |
| `website/` | Cloudflare Worker — landing, privacy and support pages. Static assets + Tailwind v4. Own `AGENTS.md` |
| `notes/` | Idea, decisions, reviews, and `changelog.md`. Not shipped |
| `tools/` | Scripts that are not part of the app: the release, the guide's captures, debug drivers, the icon |

Bundle ids are always `com.aliemir.*`.

## Working on the app

The agent owns the app end to end — idea, code, website, release — not just
the Swift. What follows is the default way of working; deviate only when asked.

### Where each kind of work goes

| Work | Home |
|---|---|
| Idea, brainstorming, critique, pivots, feature proposals, research, review write-ups | `notes/` |
| Running log of what was done and when | `notes/changelog.md` |
| Decisions worth not relitigating, with the rejected options | `notes/decisions.md` |
| Landing, privacy and support pages | `website/` |

Nothing about the idea or the plan lives only in the conversation. If it was
worth thinking about, it is in `notes/` before the session ends.

### Pictures are reproducible, not hand-shot

The guide's pictures and GIFs and the website's pictures and videos come from
`tools/capture-guide.sh`: it drives a debug copy on a throwaway library into
the same screens every time. Re-run it after a UI change rather than shooting
one picture by hand; keep only the pictures that actually changed.

### Releases

`tools/release.sh <version>` is the whole path: version bump, Release archive,
Developer ID signing, notarization and stapling (the app, then the DMG), and a
GitHub Release with `Galley.dmg` attached. `--local` stops after a signed DMG
on this Mac, for checking the build without publishing. Publishing a release
is outward-facing: run it without `--local` only when the user asks for a
release.

### Changelog and commits

Commit as the work lands, not at the end. Asked for three things, a session
produces at least three commits — one per logical change, each committed when
that piece is done rather than held until the rest finish. Collapsing a whole
session into one commit throws away the history that makes a change reviewable
and revertable one piece at a time; do not do it.

`notes/changelog.md` is a running log — newest first, dated, one entry per
meaningful step — written alongside its commit rather than reconstructed from
memory at the end. Commits follow Conventional Commits
(`conventional-commit` skill).

### Idea work is invited

Criticising the idea, proposing a pivot, suggesting features, arguing the app
into the best version of itself — all fair game, all written down in `notes/`.
The `grilling` skill is for stress-testing a plan on request.

## Commands

```bash
# build
xcodebuild -project app/Galley.xcodeproj -scheme Galley \
  -destination 'platform=macOS' build

# test — unit tests only; drop -only-testing to include UI tests (see Gotchas)
xcodebuild -project app/Galley.xcodeproj -scheme Galley \
  -destination 'platform=macOS' test -only-testing:GalleyTests

# run a debug build on a sample workspace, then drive and snapshot it
open app/…/Debug/Galley.app --args -GalleyOpen app/Fixtures/Showcase
swift tools/galley-debug.swift level.3 theme.sepia open.1 snapshot
#   → /private/tmp/galley-debug/snapshot.png (chrome + page, no permissions)
#   commands: level.N theme.<id> open.N next fold unfold scroll.N highlight
#             palette dark light resize.small|large reset probe snapshot
#             appearance[.close] find[.close] settings[.reading|.appearance|.close]
#             swipe.right|left|hold|release|wobble pull.hold|back|release
#             (trackpad gestures fed through the real GestureMonitor)
#             js (runs /private/tmp/galley-debug/eval.js in the page, logs
#             the result to stderr — measure layout, read scroll position)
#             focusfiles type.<text> key.return|escape|down (real key events
#             posted to the window) rail[.off] identity[.close] icon.test|reset
#             columns.reset|filesfirst|nocontents toggle.<column>
#             divider.narrow|wide (drives the Workspaces edge-drag steps)
#             tab.new|newnext|next|close|others|move|state (state logs the
#             tabs and workspaces) key.ctrltab|ctrlshifttab|cmdw|cmdt|cmdreturn|backspace|tab
#             menus (logs every menu shortcut) opened.remove shortcut.test|reset
#             settings.general|reading|themes|shortcuts|icon|agents agents[.close]
# open a single file as Finder would (outside a workspace → Opened Files):
open -a app/…/Debug/Galley.app /path/to/file.md
# the Galley Guide's pictures and GIFs (ffmpeg): a debug copy on a throwaway library
# (-GalleyLibrary <dir>) and a copy of the Showcase workspace
tools/capture-guide.sh
# real on-screen captures (needs Screen Recording for the terminal) —
# popovers and Settings are their own windows, so capture by window id:
swift tools/window-bounds.swift Galley     # id layer x,y,w,h title
screencapture -x -o -l <id> shot.png

# the galley command (the app binary in command mode); GALLEY_LIBRARY=<dir>
# points a debug build at a throwaway library instead of the reader's
app/…/Debug/Galley.app/Contents/MacOS/Galley --cli help
app/…/Debug/Galley.app/Contents/MacOS/Galley --cli feedback app/Fixtures/Showcase

# regenerate the placeholder app icon
swift tools/make-icon.swift app/Galley/Assets.xcassets/AppIcon.appiconset

# website — landing, privacy, support
cd website && npm run dev      # npm run deploy to ship (both build Tailwind first)

# release — see Releases above
tools/release.sh 1.0.0 --local # signed DMG in build/release/, nothing published
tools/release.sh 1.0.0         # notarized, tagged, published on GitHub
```

Prefer the `xcodebuildmcp` CLI over raw `xcodebuild`/`xcrun` where it covers
the task — see the `xcodebuildmcp-cli` skill (use its macOS commands, not the
simulator ones).

## Gotchas

- **Mac only, no simulator.** The app builds and runs natively on this Mac
  (`-destination 'platform=macOS'`). There is no iOS target; do not boot a
  simulator for it, and do not add iOS back without being asked.
- **UI tests drive the real desktop.** On macOS they move the user's actual
  mouse and keyboard and may trigger an Accessibility prompt. Run unit tests
  (`-only-testing:GalleyTests`) by default; run UI tests only when
  they are the point, and say so first. Quit the app after `build-and-run`.
- **No App Sandbox; the reader page is the locked part.** Galley ships from
  GitHub (Developer ID, notarized), not the App Store, so
  `ENABLE_APP_SANDBOX = NO` and there are no entitlements files. The page
  stays shut: its CSP allows only `galley:` and `data:` (no network, no inline
  script), navigation is cancelled in Swift, and raw HTML is cleaned by the
  renderer. If the sandbox ever comes back, WebKit needs
  `ENABLE_OUTGOING_NETWORK_CONNECTIONS` or the page sticks at 10%.
- **The data left the sandbox container once.** `SandboxMigration` copies the
  library and settings out of `~/Library/Containers/com.aliemir.galley` on the
  first unsandboxed launch. macOS guards that container from other processes:
  a Galley started from a terminal (its binary run directly) is the
  terminal's process and cannot read it — start it with `open` when testing
  the copy.
- **One Galley at a time.** Each running copy keeps the whole library in
  memory and writes `library.json` in full, so two copies (a test build
  launched by its binary while the user's is open) overwrite each other's
  highlights, notes and pins — last writer wins. `pkill -x Galley` before
  launching a test build, and don't drive the app while the user is using
  it (check `ioreg -c IOHIDSystem` idle time). Test highlights and notes on
  fixture files the user has not marked up. `xcodebuild test` launches the
  debug app as its test host on the reader's real library and can leave it
  running after the run — `pkill -x Galley` once tests finish, and before
  `open`ing a test copy: `open` on an app that is already running only brings
  that copy forward, ignoring the new `--args`.
- **A test copy keeps its own settings.** A debug build launched with
  `-GalleyLibrary` reads and writes `com.aliemir.galley.test` (emptied each
  launch) instead of the reader's preferences, through `Preferences.store` —
  every settings read and write goes through it, `@AppStorage` included
  (`store: Preferences.store`). Launch arguments (`-lightTheme sepia`) still
  apply. Without `-GalleyLibrary`, a debug build is the reader's app.
- **A test copy installs into its own home.** The palette and Settings can
  install the agent skill into `~/.agents`, `~/.claude` and `~/.gemini`. Launch
  test copies with `GALLEY_HOME=<throwaway dir>` (debug builds only) so an
  action run by a test lands there — the capture script does. `open --args`
  cannot set it; run the binary directly.
- **Debug output goes to stderr** (`debugLog`) — stdout is block-buffered when
  the app is launched from a script, so `print` output is lost.
- **Bundle resources are flattened.** Files under `app/Galley/Reader/Web/`
  (including `vendor/fonts/`) land at the bundle root; the `galley://app/`
  handler looks them up by name. Names must stay unique.
- **Read-only is a rule of the code, not the sandbox.** The app never writes
  to a Markdown file. Workspaces still store security-scoped bookmarks (from
  the sandboxed days); they resolve fine unsandboxed and fall back to the path.
- **Flat plist keys are build settings.** `GENERATE_INFOPLIST_FILE = YES`, so
  plist keys live as `INFOPLIST_KEY_*` build settings in `project.pbxproj`. To
  add a usage description or `ITSAppUsesNonExemptEncryption`, add the build
  setting — not a key in `app/Info.plist`, which is only for nested values.
- **Nested plist values need a real file, placed outside the target folder.**
  `INFOPLIST_KEY_*` only carries flat values, so `CFBundleURLTypes`,
  `NSAppTransportSecurity` and friends need the partial `app/Info.plist` (it
  exists: Markdown and folder document types, the Markdown type import) and
  `INFOPLIST_FILE = Info.plist;` on the app target's two configs. Xcode merges
  it with the generated keys. It must NOT go in `app/<Target>/`: the project
  uses file-system synchronized groups, so anything in that folder is added to
  the target automatically, and an `Info.plist` there gets copied as a resource
  as well as generated — failing the build with
  `Multiple commands produce ... Info.plist`.
- **Synchronized groups mean the folder is the target.** New Swift files in
  `app/<Target>/` are compiled with no pbxproj edit. The flip side is that any
  stray file in there is bundled too.
- **Swift 5 language mode.** `SWIFT_VERSION = 5.0` with
  `SWIFT_APPROACHABLE_CONCURRENCY = YES`, not Swift 6 strict concurrency.
- **Version settings appear once per build configuration.** Edits to
  `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` must hit Debug and Release
  together or the two drift apart.
- **`website/public/style.css` is generated, not source.** Tailwind v4 builds it
  from `website/input.css`, and it is git-ignored. `npm run dev` and
  `npm run deploy` build it first — a bare `npx wrangler deploy` ships the page
  with a missing stylesheet. Edit `input.css`, never `public/style.css`.

## Secrets

- Never commit secrets. `.env` and `*.p8` are git-ignored; `*.p8` is ignored
  repo-wide so a stray key cannot be committed from any directory.
- `.env` holds what the release needs: the App Store Connect API key's issuer
  and key id (notarytool signs in with it) and the team id. The `.p8` lives at
  `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`, outside the repo.
- Read config with `set -a; source .env; set +a`.
- Commits use the GitHub no-reply address, not a personal one.

## Decisions — do not undo these without being asked

- **No fastlane.** Releases are `xcodebuild`, `notarytool`, `hdiutil` and `gh`
  in `tools/release.sh`. Do not add fastlane, a `Gemfile`, or `fastlane/`.
- **Skills live in `.agents/skills/<name>/`**, symlinked from
  `.claude/skills/<name>` with a relative path. Add new skills the same way so
  every agent tool sees them.
- **`CLAUDE.md` is a symlink to this file.** Edit `AGENTS.md`.

## Skills

`xcodebuildmcp-cli` (build/test/run) · `swiftui-pro` (SwiftUI review) ·
`frontend-design` (the website) · `conventional-commit` · `grilling`
