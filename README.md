# Galley

| | |
|---|---|
| Bundle id | `com.aliemir.galley` |
| Xcode target | `Galley` |
| Backend Worker | `galley-api` |
| Website Worker | `galley-website` |

## Layout

- `app/` — the macOS app (`app/Galley.xcodeproj`)
- `backend/` — API Cloudflare Worker (`npm run dev` / `npm run deploy`)
- `website/` — marketing / privacy / support site, Worker + Tailwind (`npm run dev`)
- `screenshot-generator/` — Remotion project for App Store screenshots and app previews (`npm run dev`)
- `store-metadata/` — App Store copy, keywords, screenshots
- `privacy-policy-template/` — source template for the privacy policy served by `website/`
- `notes/` — project notes, decisions, scratch
- `.env` — App Store Connect ids (git-ignored; the `.p8` lives in `~/.appstoreconnect/private_keys/`)

## Setup

```sh
cp .env.example .env      # fill in App Store Connect issuer + key id
./check.sh                # verify toolchain, signing key and .env
open app/Galley.xcodeproj
```
