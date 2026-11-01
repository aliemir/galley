#!/bin/zsh
# Captures the pictures in the Galley Guide (app/Galley/Guide/) from the
# debug build: a throwaway library on a copy of the Showcase workspace, the
# Paper theme passed at launch, so the reader's own library and settings are
# never touched. Needs Screen Recording for the terminal, and ffmpeg
# (Homebrew) for the GIFs (recorded by tools/record-window.swift). Quits any running Galley first (one Galley at a
# time — see AGENTS.md).
#
# Usage: tools/capture-guide.sh   (after building the Debug scheme)
set -euo pipefail
cd "$(dirname "$0")/.."

PRODUCTS=$(xcodebuild -project app/Galley.xcodeproj -scheme Galley -configuration Debug -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
APP="$PRODUCTS/Galley.app"
WORK=/private/tmp/galley-debug/guide
OUT=app/Galley/Guide

debug() { swift tools/galley-debug.swift "$@"; }

# The largest Galley window, or the one with this title.
window() {
  swift tools/window-bounds.swift Galley | awk -v title="${1:-}" '
    { split($3, f, ","); area = f[3] * f[4]; name = $4; for (i = 5; i <= NF; i++) name = name " " $i }
    title != "" && name == title { print $1; found = 1; exit }
    title == "" && area > best { best = area; id = $1 }
    END { if (title == "" && !found) print id }'
}

# shot <name> <window id> [crop: height width y x] — window pixels at 2x,
# resampled to at most 1600 wide.
shot() {
  local file="$OUT/guide-$1.png"
  screencapture -x -o -l "$2" "$file"
  if [[ $# -ge 6 ]]; then sips -c "$3" "$4" --cropOffset "$5" "$6" "$file" --out "$file" >/dev/null; fi
  if (( $(sips -g pixelWidth "$file" | awk '/pixelWidth/{print $2}') > 1600 )); then
    sips --resampleWidth 1600 "$file" --out "$file" >/dev/null
  fi
  # Finder info from screencapture and sips fails code signing.
  xattr -c "$file"
  echo "wrote $file"
}

# gif <name> <seconds> <debug commands…>: records the main window — that
# window alone, so nothing in front of it gets in — while the commands run,
# then makes a GIF. The window's top strip is cropped off: macOS badges a
# window being recorded where its traffic lights are.
gif() {
  local name=$1 seconds=$2; shift 2
  local frames="$WORK/$name-frames"
  rm -rf "$frames"
  swift tools/record-window.swift "$(window)" "$seconds" 15 "$frames" &
  local recording=$!
  sleep 1.6
  debug "$@"
  wait $recording
  ffmpeg -loglevel error -y -framerate "$(cat "$frames/rate")" -i "$frames/frame%05d.png" \
    -vf "crop=iw-24:ih-52:12:40,fps=12,scale=760:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    "$OUT/guide-$name.gif"
  xattr -c "$OUT/guide-$name.gif"
  echo "wrote $OUT/guide-$name.gif"
}

osascript -e 'tell application id "com.aliemir.galley" to quit' 2>/dev/null || true
sleep 1
rm -rf "$WORK" && mkdir -p "$WORK"
cp -R app/Fixtures/Showcase "$WORK/Showcase"

# More workspaces, so the rail looks like a day's work: agent output from
# three other projects.
mkdir -p "$WORK/ios-app/plans" "$WORK/api-gateway/docs" "$WORK/design-notes"
cat > "$WORK/ios-app/plans/onboarding-redesign.md" <<'MD'
# Onboarding redesign

Three screens instead of five, and the account step moves to the end.
MD
cat > "$WORK/ios-app/release-checklist.md" <<'MD'
# Release checklist

- [x] Bump the build number
- [ ] Screenshots for the new onboarding
MD
cat > "$WORK/api-gateway/docs/rate-limit-design.md" <<'MD'
# Rate limit design

Token buckets per API key, refilled every second.
MD
cat > "$WORK/api-gateway/README.md" <<'MD'
# API gateway

Routes, auth and rate limits for the public API.
MD
cat > "$WORK/design-notes/type-scale.md" <<'MD'
# Type scale

Body 17 pt, headings on a 1.25 ratio.
MD

"$APP/Contents/MacOS/Galley" -GalleyLibrary "$WORK/library" -GalleyOpen "$WORK/Showcase" \
  -appearance light -lightTheme paper -font newYork -fontSize 17 >"$WORK/log.txt" 2>&1 &
sleep 5
open "$APP"   # to the front: captures of a window behind others can be stale
sleep 1
open -a "$APP" "$WORK/ios-app" "$WORK/api-gateway" "$WORK/design-notes"
sleep 3
# Written after the workspace was opened: new, so its rail icon gets a dot.
cat > "$WORK/ios-app/plans/paywall-copy.md" <<'MD'
# Paywall copy

Lead with what the free tier keeps.
MD
sleep 2
debug dress ws.0 wait.800 resize.large level.4 open.1 wait.2500

# 1. The whole window: rail, files, contents, page.
shot overview "$(window)"

# 2. Changes: read the rate-limits note, leave it, let an "agent" edit it.
debug open.2 wait.3200 open.1 wait.800
python3 - "$WORK/Showcase/plans/api-rate-limits.md" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("Move to a token bucket refilled every second, so a burst is spent and earned\nback smoothly instead of resetting on the minute.",
              "Move to a token bucket refilled every second, so a burst is spent and earned\nback gradually instead of resetting at the top of every minute.\n\nInternal tools keep their current limits until the second wave; their\ntraffic is too spiky to tune before we have a week of bucket metrics.")
open(p, "w").write(s)
EOF
sleep 2
debug level.1 open.2 wait.2500
shot changes "$(window)" 860 1480 330 700

# 3. Feedback: a highlight with a note under it, on the plan.
debug open.1 wait.1500 highlight.note wait.1800
shot feedback "$(window)" 1100 1480 120 700

# 4. Go to File, before typing: the most recent files.
debug level.3 palette wait.1500
shot palette "$(window)"
debug palette.close

# 5. The theme gallery.
debug settings.themes wait.1800
shot themes "$(window Themes)"
debug settings.close wait.300

# 6. GIFs, in a smaller window so they stay light.
debug resize.small level.1 open.1 wait.1500
gif columns 7 swipe.slowright wait.1400 swipe.slowright wait.1400 swipe.slowleft wait.1200 swipe.slowleft
debug level.1 open.3 wait.1500 scroll.bottom wait.900
gif pull 5 pull.slow

osascript -e 'tell application id "com.aliemir.galley" to quit' 2>/dev/null || true
# The website shows the same pictures.
cp "$OUT"/guide-*.png "$OUT"/guide-*.gif website/public/images/
echo "done — check $OUT/guide-*.png"
