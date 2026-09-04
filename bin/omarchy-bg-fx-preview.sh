#!/bin/bash
# Generate (or reuse) a real ttfx effect preview video for the background
# switcher. The preview is a recording of the actual terminaltexteffects
# engine (same one the audio-background plugin drives), rendered to an mp4
# loop plus a poster frame.
#
# Usage: omarchy-bg-fx-preview.sh <effect>
# Cache: ~/.cache/omarchy/fx-previews/<effect>.mp4 (live media)
# Posters: ~/Backgrounds/ASCII/<effect>.jpg (static frame for unselected items)
set -e

FX="${1:-}"
if [[ -z "$FX" ]]; then
  echo "usage: omarchy-bg-fx-preview.sh <effect-name>" >&2
  exit 1
fi

CACHE_DIR="$HOME/.cache/omarchy/fx-previews"
mkdir -p "$CACHE_DIR"
OUT="$CACHE_DIR/$FX.mp4"
POSTER_DIR="$HOME/Wallpapers/ASCII"
mkdir -p "$POSTER_DIR"
POSTER="$POSTER_DIR/$FX.jpg"
[[ -f "$OUT" && -f "$POSTER" ]] && { echo "$OUT"; exit 0; }

# ttfx CLI: needed only to (re)generate preview videos/posters for the
# switcher's ASCII category. Optional — everything works with the shipped
# posters; without ttfx the generation just skips.
TTFX_BIN="${TTFX_BIN:-$(command -v ttfx 2>/dev/null || true)}"
if [[ -z "$TTFX_BIN" || ! -x "$TTFX_BIN" ]]; then
  echo "ttfx binary not found (set TTFX_BIN to generate previews)" >&2
  exit 1
fi

# Pillow for the ANSI renderer (PEP 668: dedicated venv)
PY="$HOME/.venv-fxpreview/bin/python"
FXRENDER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fxrender.py"
CAPTURE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fxcapture.py"
if [[ ! -x "$PY" ]]; then
  PY="$(command -v python3)"
  if ! "$PY" -c 'import PIL' 2>/dev/null; then
    echo "Pillow required (venv at ~/.venv-fxpreview or system python3-PIL)" >&2
    exit 1
  fi
fi

# Render at the EXPANDED slice's exact size (768x475) so previews are 1:1
# pixels with the item — no upscale blur. 768/8 = 96 cols, 475/14 = 34 rows.
CW=96; CH=34; FRAMERATE=15; SECS=15
# Center the text in the canvas: with the default southwest anchor the words
# sit in a bottom corner and 90% of the preview frame reads as empty black.
ANCHOR_ARGS="--anchor-canvas c --anchor-text c"
INPUT="$(mktemp /tmp/fx-input.XXXXXX)"
STREAM="$(mktemp /tmp/fx-stream.XXXXXX)"
FRAMES="$(mktemp -d /tmp/fx-frames.XXXXXX)"
trap 'rm -f "$INPUT" "$STREAM"; rm -rf "$FRAMES"' EXIT

printf 'OMARCHY\nAUDIO FX\n' > "$INPUT"

# ttfx writes to the tty, not stdout, and sizes its canvas against the tty
# window — so run it under a pty we control (fxcapture sets TIOCSWINSZ big
# enough for the canvas). script(1) would truncate frames to its own size.
"$PY" "$CAPTURE" "$STREAM" "$CW" "$CH" "$SECS" -- \
  "$TTFX_BIN" --input-file "$INPUT" --canvas-width "$CW" --canvas-height "$CH" \
  $ANCHOR_ARGS --frame-rate "$FRAMERATE" --seed 7 "$FX" || true

"$PY" "$FXRENDER" "$STREAM" "$FRAMES" "$CW" "$CH" $((SECS * FRAMERATE)) >/dev/null

ffmpeg -y -loglevel error -framerate "$FRAMERATE" -i "$FRAMES/f%04d.png" \
  -c:v libx264 -pix_fmt yuv420p -crf 23 -movflags +faststart "$OUT"

# tte effects settle and clear the canvas before the CLI exits (the real
# background wrapper loops them). Cut the loop to the developed span so the
# preview never sits on an empty black frame.
read -r FIRST_GOOD LAST_GOOD < "$FRAMES/lastgood.txt" || { FIRST_GOOD=0; LAST_GOOD=$((SECS * FRAMERATE - 1)); }
if [[ "$LAST_GOOD" -lt "$((SECS * FRAMERATE - 1))" || "$FIRST_GOOD" -gt 0 ]]; then
  CUT="$FRAMES/cut.mp4"
  ffmpeg -y -loglevel error -framerate "$FRAMERATE" -i "$FRAMES/f%04d.png" \
    -vf "select='between(n\,$FIRST_GOOD\,$LAST_GOOD)',setpts=N/FRAME_RATE/TB" \
    -c:v libx264 -pix_fmt yuv420p -crf 23 -movflags +faststart "$CUT"
  [[ -f "$CUT" ]] && mv "$CUT" "$OUT"
fi

# poster: the most-developed frame (some effects are intermittently dark)
cp "$FRAMES/best.png" "$POSTER"

echo "$OUT"
