#!/bin/zsh
# Builds a Galley release and publishes it on GitHub: the version bumped and
# committed, a Release archive exported with the Developer ID certificate,
# the app notarized and stapled, a drag-to-Applications DMG signed, notarized
# and stapled, then the commit and a v<version> tag pushed and a GitHub
# Release created with Galley.dmg attached — a stable name, so the website's
# …/releases/latest/download/Galley.dmg always serves the newest build.
#
# Usage:
#   tools/release.sh <version>            # e.g. 1.0.0 — the whole way
#   tools/release.sh <version> --local    # a signed DMG in build/release/ only:
#                                         # no bump, no notarizing, nothing pushed
#
# Needs (checked first, for the full run):
#   - a "Developer ID Application" certificate in the keychain
#     (Xcode → Settings → Accounts → Manage Certificates → + )
#   - .env with APP_STORE_CONNECT_ISSUER_ID, _KEY_ID, _KEY_PATH (notarytool
#     signs in with that key) and APPLE_TEAM_ID — see .env.example
#   - gh, signed in (`brew install gh`, then `gh auth login`)
#   - a clean tree on main
# Release notes: notes/release-notes/<version>.md when it exists; otherwise
# the feat and fix commits since the last tag, written to build/release/notes.md.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { print -u2 "release: $*"; exit 1; }
step() { print "\n▸ $*"; }

VERSION=${1:-}
LOCAL=false
[[ ${2:-} == --local ]] && LOCAL=true
[[ $VERSION =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || die "usage: tools/release.sh <major.minor.patch> [--local]"
TAG="v$VERSION"

OUT=build/release
ARCHIVE=$OUT/Galley.xcarchive
DMG=$OUT/Galley.dmg
PROJECT=app/Galley.xcodeproj

DEVELOPER_ID=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)

# — Preflight ——————————————————————————————————————————————————————————
step "Checking"
if [[ $LOCAL == false ]]; then
  [[ -n $DEVELOPER_ID ]] || die "no Developer ID Application certificate — create one in Xcode → Settings → Accounts → Manage Certificates"
  [[ -f .env ]] || die "no .env — copy .env.example and fill it in"
  set -a; source .env; set +a
  for name in APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_KEY_ID APP_STORE_CONNECT_KEY_PATH APPLE_TEAM_ID; do
    [[ -n ${(P)name:-} ]] || die "$name is empty in .env"
  done
  [[ -f $APP_STORE_CONNECT_KEY_PATH ]] || die "no key at $APP_STORE_CONNECT_KEY_PATH"
  command -v gh >/dev/null || die "gh is not installed — brew install gh, then gh auth login"
  gh auth status >/dev/null 2>&1 || die "gh is not signed in — gh auth login"
  [[ $(git branch --show-current) == main ]] || die "not on main"
  [[ -z $(git status --porcelain) ]] || die "the tree has uncommitted changes"
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "$TAG already exists"
  git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1 && die "$TAG already exists on origin"
fi
print "  version $VERSION$([[ $LOCAL == true ]] && print ' (local)')"
print "  signing ${DEVELOPER_ID:-with the development certificate (no Developer ID yet)}"

# — Version ————————————————————————————————————————————————————————————
# The build number only ever grows: the number of commits, after the bump.
BUILD=$(( $(git rev-list --count HEAD) + 1 ))
if [[ $LOCAL == false ]]; then
  step "Bumping to $VERSION ($BUILD)"
  # Every configuration at once, so Debug and Release never drift apart.
  sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/; s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $BUILD;/" $PROJECT/project.pbxproj
  git add $PROJECT/project.pbxproj
  git commit -q -m "chore(release): $VERSION"
fi

# — Build ——————————————————————————————————————————————————————————————
step "Archiving"
rm -rf $OUT && mkdir -p $OUT
xcodebuild -project $PROJECT -scheme Galley -configuration Release -destination 'generic/platform=macOS' \
  -archivePath $ARCHIVE MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$BUILD archive -quiet

if [[ -n $DEVELOPER_ID ]]; then
  step "Exporting with Developer ID"
  cat > $OUT/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>teamID</key><string>${APPLE_TEAM_ID:-$(print $DEVELOPER_ID | sed -n 's/.*(\(.*\))/\1/p')}</string>
</dict></plist>
EOF
  xcodebuild -exportArchive -archivePath $ARCHIVE -exportPath $OUT/export -exportOptionsPlist $OUT/ExportOptions.plist -quiet
  APP=$OUT/export/Galley.app
else
  # --local without the certificate: the archive's own development signature.
  APP=$ARCHIVE/Products/Applications/Galley.app
fi

step "Checking the signature"
codesign --verify --deep --strict $APP || die "the app's signature does not verify"
# Read once: grep -q closing the pipe early would fail it under pipefail.
SIGNATURE=$(codesign -dvv $APP 2>&1)
[[ $SIGNATURE == *flags=*runtime* ]] || die "the app is not signed with the hardened runtime"
SIGNATURE_LINES=(${(f)SIGNATURE})
SIGNER=${${(M)SIGNATURE_LINES:#Authority=*}[1]}
print "  signed by ${SIGNER#Authority=}"

notarize() {
  local file=$1 result id
  result=$(xcrun notarytool submit $file --key $APP_STORE_CONNECT_KEY_PATH --key-id $APP_STORE_CONNECT_KEY_ID \
    --issuer $APP_STORE_CONNECT_ISSUER_ID --wait --output-format json)
  id=$(print -r -- $result | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  if ! print -r -- $result | grep -q '"status" *: *"Accepted"'; then
    xcrun notarytool log $id --key $APP_STORE_CONNECT_KEY_PATH --key-id $APP_STORE_CONNECT_KEY_ID --issuer $APP_STORE_CONNECT_ISSUER_ID >&2 || true
    die "notarization of $file was not accepted (submission $id)"
  fi
  print "  accepted ($id)"
}

if [[ $LOCAL == false ]]; then
  # The app first, stapled, so a copy dragged out of the DMG opens offline too.
  step "Notarizing the app"
  ditto -c -k --keepParent $APP $OUT/Galley-notarize.zip
  notarize $OUT/Galley-notarize.zip
  xcrun stapler staple -q $APP
  rm $OUT/Galley-notarize.zip
fi

# — DMG ————————————————————————————————————————————————————————————————
step "Making Galley.dmg"
STAGE=$OUT/dmg
mkdir -p $STAGE
ditto $APP $STAGE/Galley.app
ln -s /Applications $STAGE/Applications
hdiutil create -quiet -volname Galley -srcfolder $STAGE -fs HFS+ -format UDZO -ov $DMG
rm -rf $STAGE
if [[ -n $DEVELOPER_ID ]]; then
  codesign --sign $DEVELOPER_ID --timestamp $DMG
fi

if [[ $LOCAL == true ]]; then
  print "\nDone: $DMG ($(du -h $DMG | cut -f1)) — not notarized, nothing published."
  exit 0
fi

step "Notarizing the DMG"
notarize $DMG
xcrun stapler staple -q $DMG
spctl --assess --type open --context context:primary-signature $DMG || die "Gatekeeper rejects the DMG"
spctl --assess --type execute $APP || die "Gatekeeper rejects the app"
print "  Gatekeeper accepts both"

# — Publish ————————————————————————————————————————————————————————————
step "Publishing $TAG"
NOTES=notes/release-notes/$VERSION.md
if [[ ! -f $NOTES ]]; then
  NOTES=$OUT/notes.md
  PREVIOUS=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)
  {
    print "## What's new\n"
    git log --format='%s' ${PREVIOUS:+$PREVIOUS..}HEAD | grep -E '^(feat|fix)(\([^)]*\))?: ' \
      | sed -E 's/^(feat|fix)(\([^)]*\))?: /- /' || print "- Maintenance."
  } > $NOTES
fi
print "\n---\nmacOS 15 or later. SHA-256 of Galley.dmg: \`$(shasum -a 256 $DMG | cut -d' ' -f1)\`" >> $NOTES

git push -q origin main
git tag -a $TAG -m "Galley $VERSION"
git push -q origin $TAG
gh release create $TAG $DMG --title "Galley $VERSION" --notes-file $NOTES
print "\nDone: $(gh release view $TAG --json url -q .url)"
