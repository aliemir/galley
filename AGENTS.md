# AGENTS.md

iOS app, two Cloudflare Workers (API + marketing site), and a Remotion project
for App Store media.

## Layout

| Path | What |
|---|---|
| `app/` | The iOS app. `app/MyAppProductName.xcodeproj` |
| `backend/` | Cloudflare Worker — the app's API. Has its own `AGENTS.md` — read it before touching Workers code |
| `website/` | Cloudflare Worker — privacy policy and support pages. Static assets + Tailwind v4. Own `AGENTS.md` |
| `screenshot-generator/` | Remotion project — App Store screenshot stills and app preview videos. Own `AGENTS.md` |
| `store-metadata/` | App Store listing copy, screenshots, review notes |
| `privacy-policy-template/` | Source text for the privacy policy `website/` serves |
| `notes/` | Idea, brainstorming, decisions, and `changelog.md`. Not shipped |
| `tools/` | Build-time scripts that are not part of the app |
| `check.sh` | Preflight — verifies the machine can build, sign and ship |
| `rename.sh` | One-shot template rename. Delete after running |

## Template

`./rename.sh` renames the Xcode project, targets, bundle ids, and both Workers
(`backend/` → `<slug>-api`, `website/` → `<slug>-website`) in one pass. It runs
once on a fresh clone and refuses to run twice.

Bundle ids are always `com.aliemir.*`.

`./check.sh` is the preflight. It has two modes and picks one itself, keyed on
whether `app/MyAppProductName.xcodeproj` still exists:

- **Template** (here) — toolchain only: full Xcode rather than Command Line
  Tools, the simulator named in the build command, `xcodebuildmcp`,
  `altool`/`notarytool`, brew/git/node/python/perl, and that git is not tracking
  a `.env` or a `.p8`. The `.env` values, the signing key and `npm install` are
  per-app, so they report as n/a — nothing to fill in in this repo.
- **App** (after `./rename.sh`) — all of the above plus `.env` filled in, the
  `.p8` present at the path `altool` searches with mode 600, dependencies
  installed, and the Tailwind build done.

Read-only — it prints the fixing command rather than running it — and exits
non-zero on a failure, so it also works as a CI gate. `--quiet` reports only
problems, which means silence when everything is fine.

## Working on an app

This repo is one app's worth of scaffolding, and the agent owns the app end to
end — idea, code, web presence, store listing, release — not just the Swift.
What follows is the default way of working; deviate only when asked.

### Where each kind of work goes

| Work | Home |
|---|---|
| Idea, brainstorming, critique, pivots, feature proposals, research, review write-ups | `notes/` |
| Running log of what was done and when | `notes/changelog.md` |
| Decisions worth not relitigating, with the rejected options | `notes/decisions.md` |
| Privacy policy, support page, marketing/landing page | `website/` |
| Anything the app needs a server for — API, secrets, receipt checks, AI proxying | `backend/` |
| Listing copy, keywords, categories, review notes, ASC questionnaire answers, final media | `store-metadata/` |
| Screenshot stills and app-preview videos | `screenshot-generator/` |

Nothing about the idea or the plan lives only in the conversation. If it was
worth thinking about, it is in `notes/` before the session ends.

### Web presence is not optional

Every app needs a **privacy policy URL** and a **support URL** that resolve —
App Store Connect requires both, and no build ships without them. Both are
served by `website/`, and both are the agent's job, not a to-do handed back to
the user. A marketing/landing page goes there too when the app wants one.

### App Store Connect is the agent's job too

The key in `.env` is there so "ship it" can mean the whole way, unattended
wherever the API allows:

- listing text and every localization pushed to ASC
- screenshots and app previews uploaded
- in-app purchases created, priced, localized
- age rating, export compliance and App Privacy answers filled in
- build uploaded, **processing polled until it completes**, then released to
  testers — internal always, external when asked
- "What's New" written per version

The `testflight-release` skill covers archive → upload. Everything past that is
the App Store Connect REST API, called directly with `curl` and an ES256 JWT
signed from the same `.env` key — no third-party CLI, no wrapper library. The
`asc-api` skill has the token recipe and the endpoints that are easy to get
wrong.

What the API cannot do is the user's to do: creating the app record, and
signing the Paid Apps and tax/banking agreements. Do not stall on them
silently — say exactly which one is blocking, where in ASC it lives, and what
to fill in, then carry on with everything that does not depend on it.

### Localization is all three layers or none

Adding a language means, in the same pass:

1. the app's own strings (String Catalog),
2. the ASC listing for that locale in `store-metadata/listing.json`,
3. a screenshot set rendered in that locale.

A localized listing behind English screenshots is worse than not localizing.

### Store media is reproducible, not hand-shot

Capture is a script in the repo, not commands retyped each session: it drives
the app into the same screens the same way for every locale, captures, then
frames and captions in `screenshot-generator/`. Write it the first time media
is needed and check it in.
That is what makes a locale cheap to add and a UI change cheap to absorb — the
whole set rebuilds instead of being re-shot. Never hand-shoot one locale and
eyeball the others. Which way the status bar goes — hidden, or pinned to
identical values with `simctl status_bar override` — is the app's call, made
once and applied to every shot in the set; a set with a drifting clock and
battery looks careless. App preview videos are optional; render them the same way
when the app wants them.

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

### Settle these per app — ask, don't invent

None of these have a template-wide answer. Ask when the work first needs one,
and record the answer in `notes/decisions.md`:

- **Domain** for the privacy/support URLs — decided per app, so ask before
  writing a URL into the listing.
- **Devices** — iPhone only or universal. It decides which screenshot sets ASC
  requires.
- **Locales**, and which one is the base.
- **Money** — free, paid, or IAP. Keep purchases on-device with StoreKit;
  `backend/` gets involved only when something genuinely cannot work without a
  server.
- **Testers** — internal only, or an external group as well (external needs
  Apple's beta review on the first build of each version).
- **Git remote** — push when one is configured; ask if it is ambiguous.

### Autonomy and spend

Uploading builds, editing the listing, releasing to testers: these do not need
per-action permission. Agree the boundary once at the start of a session and
scale it to severity — a TestFlight build is cheap and reversible, an App Store
submission and a price change are not.

There is no hard budget cap on generated images or API calls. Agree a number
for the session when a task is going to burn through them, and say so when the
work is heading past it rather than stopping silently.

## Commands

```bash
# preflight — toolchain, signing key, .env, repo hygiene
./check.sh            # --quiet for problems only

# build
xcodebuild -project app/MyAppProductName.xcodeproj -scheme MyAppProductName \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# test
xcodebuild -project app/MyAppProductName.xcodeproj -scheme MyAppProductName \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# backend — the API worker
cd backend && npm run dev      # npm run deploy to ship

# website — privacy + support pages
cd website && npm run dev      # npm run deploy to ship (both build Tailwind first)

# screenshots + app previews
cd screenshot-generator && npm run dev                 # Remotion Studio
npx remotion still  <Composition> out/shot.jpeg --image-format=jpeg
npx remotion render <Composition> out/preview.mp4
```

Prefer the `xcodebuildmcp` CLI over raw `xcodebuild`/`xcrun`/`simctl` where it
covers the task — see the `xcodebuildmcp-cli` skill.

## Gotchas

- **One simulator at a time.** This machine cannot handle several booted
  simulators — it freezes. Before booting or running, check
  `xcrun simctl list devices booted` and shut down what is already up
  (`xcrun simctl shutdown <udid>`, or `xcrun simctl shutdown all`); reuse the
  booted one instead of booting a second. Never fan out builds or UI tests
  across simulators in parallel, and never leave one booted after the task.
  A second simulator is only acceptable when the thing being tested genuinely
  needs two devices at once — say so before booting it, and shut it down after.
- **There is no `Info.plist` file.** `GENERATE_INFOPLIST_FILE = YES`, so plist
  keys live as `INFOPLIST_KEY_*` build settings in `project.pbxproj`. To add a
  usage description or `ITSAppUsesNonExemptEncryption`, add the build setting —
  do not create an `Info.plist`.
- **Nested plist values need a real file, placed outside the target folder.**
  `INFOPLIST_KEY_*` only carries flat values, so `CFBundleURLTypes`,
  `NSAppTransportSecurity` and friends need a partial `app/Info.plist` plus
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
- **App Store screenshots are rejected if they carry an alpha channel.** A
  Remotion canvas is transparent unless the composition paints a background, and
  `remotion still` writes PNG by default. Render stills with
  `--image-format=jpeg`, or paint an opaque `AbsoluteFill` and confirm with
  `sips -g hasAlpha <file>`. A composition's `width`/`height` are the output
  pixels, so they must match the exact sizes in `store-metadata/GUIDE.md`.

## Secrets

- Never commit secrets. `.env` and `*.p8` are git-ignored; `*.p8` is ignored
  repo-wide so a stray key cannot be committed from any directory.
- The App Store Connect key lives at
  `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`, outside the repo.
  That path is where `altool` searches, so `--apiKey <KEY_ID>` resolves it with
  no path argument.
- Read config with `set -a; source .env; set +a`.
- API keys for third-party services belong in the Worker as
  `wrangler secret put`, never in the iOS binary.

## Decisions — do not undo these without being asked

- **No fastlane.** Deliberately removed. Releases go out via `xcodebuild` +
  `xcrun altool` — see the `testflight-release` skill. Do not reintroduce
  fastlane, a `Gemfile`, or a `fastlane/` directory.
- **App Store Connect is driven by its REST API directly.** `curl` plus an
  ES256 JWT from the `.env` key — see the `asc-api` skill. No third-party ASC
  CLI, SDK or wrapper: it is one more dependency to trust and to keep current,
  and the API is plain HTTP.
- **The App Store Connect OpenAPI spec is checked in** at
  `.agents/skills/asc-api/openapi.json`, ~7 MB. It is the repo's largest file
  and that is deliberate: it makes the `asc-api` skill work on a fresh clone
  with no setup. Do not delete it as bloat; replace it wholesale to update it,
  and query it with `jq` rather than opening it.
- **`backend/`, `website/` and `screenshot-generator/` stay even when unused.**
  All three are scaffolding kept ready on purpose. Do not delete them as dead
  code.
- **Skills live in `.agents/skills/<name>/`**, symlinked from
  `.claude/skills/<name>` with a relative path. Add new skills the same way so
  every agent tool sees them. `screenshot-generator/` follows the same
  convention for its own directory-scoped `remotion-*` skills — keep them
  symlinks, not copies.
- **`CLAUDE.md` is a symlink to this file.** Edit `AGENTS.md`.

## Skills

`testflight-release` (shipping) · `asc-api` (App Store Connect REST) ·
`xcodebuildmcp-cli` (build/test/run) ·
`swiftui-pro` (SwiftUI review) · `apple-appstore-reviewer` (pre-submission) ·
`workers-best-practices` (backend + website) ·
`conventional-commit` · `grilling`

Scoped to `screenshot-generator/`: `remotion-create` · `remotion-render` ·
`remotion-best-practices` · `remotion-markup` · `remotion-captions` ·
`remotion-docs` · `remotion-upgrade`
