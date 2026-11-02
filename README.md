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

## Build

```sh
open app/Galley.xcodeproj
xcodebuild -project app/Galley.xcodeproj -scheme Galley -destination 'platform=macOS' build
```

## Release

```sh
cp .env.example .env          # notarization key ids and team id
tools/release.sh 1.0.0 --local   # a signed DMG, nothing published
tools/release.sh 1.0.0           # notarized and published on GitHub Releases
```

## Licence

MIT — see [LICENSE](LICENSE). Bundled third-party code and fonts keep their own
licences, listed in `app/Galley/Reader/Web/vendor/Acknowledgements.txt`.
