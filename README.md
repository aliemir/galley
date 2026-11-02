# Galley

A calm Mac reader for the Markdown your AI agents write. It marks what changed
since you last read a file, lets you highlight and note passages, and hands that
feedback back to your agent — by copying it, or through the `galley` command
and its agent skill.

Free and open source. macOS 15 or later.

## Layout

- `app/` — the macOS app (`app/Galley.xcodeproj`)
- `website/` — the landing, privacy and support pages (Cloudflare Worker + Tailwind)
- `tools/` — release, captures, debug drivers
- `notes/` — idea, decisions, changelog

## Build it yourself

You need a Mac with Xcode (macOS 15 or later to run it). Swift packages
resolve on the first build; everything else is in the repo.

1. Open `app/Galley.xcodeproj`.
2. In the Galley target's **Signing & Capabilities**, pick your own team — or
   *Sign to Run Locally* — and, if you like, your own bundle identifier.
3. Build and run (⌘R), or from the terminal:

```sh
xcodebuild -project app/Galley.xcodeproj -scheme Galley -destination 'platform=macOS' build
```

A build of your own keeps its library in `~/Library/Application Support/Galley`,
the same place as the released app, so use one or the other at a time.

## Release

```sh
cp .env.example .env          # notarization key ids and team id
tools/release.sh 1.0.0 --local   # a signed DMG, nothing published
tools/release.sh 1.0.0           # notarized and published on GitHub Releases
```

## Licence

MIT — see [LICENSE](LICENSE). Bundled third-party code and fonts keep their own
licences, listed in `app/Galley/Reader/Web/vendor/Acknowledgements.txt`.
