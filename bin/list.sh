#!/bin/bash
# List background sources by category.
# Output columns: type <TAB> path <TAB> name <TAB> preview <TAB> media <TAB> applied
#   path    = original file, shown in the picker / used for restore
#   preview = static thumb/poster shown instantly under live media
#   media   = playable video path (video/animated), empty otherwise
#   applied = path the switcher actually applies (matches bg-source-path)

CATEGORY="${1:-image}"
THEME_NAME=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THUMB_BIN="$PLUGIN_DIR/thumb.sh"

# Bins shipped next to this script win over PATH (the plugin dir is not on
# the user's PATH on a stock Omarchy install).
pick_bin() {
  local name="$1" p=""
  p="$(command -v "$name" 2>/dev/null || true)"
  [[ -z "$p" && -x "$PLUGIN_DIR/$name" ]] && p="$PLUGIN_DIR/$name"
  printf '%s' "$p"
}

case "$CATEGORY" in
  image)
    # Theme backgrounds first, then the user's own ~/Wallpapers/Images.
    dirs=(
      "$HOME/.local/state/omarchy/current/theme/backgrounds"
      "$HOME/.config/omarchy/backgrounds/$THEME_NAME"
      "$HOME/Wallpapers/Images"
    )
    for dir in "${dirs[@]}"; do
      [[ -d "$dir" ]] || continue
      find -L "$dir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.bmp' \) -print0 2>/dev/null |
        sort -z | while IFS= read -r -d '' f; do
          name=$(basename "$f" | sed 's/\.[^.]*$//')
          printf 'image\t%s\t%s\t%s\t%s\t%s\n' "$f" "$name" "$f" "" "$f"
        done
    done
    ;;
  video)
    dir="$HOME/Wallpapers/Videos"
    [[ -d "$dir" ]] || exit 0
    find -L "$dir" -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.mov' -o -iname '*.webm' -o -iname '*.avi' \) -print0 2>/dev/null |
      sort -z | while IFS= read -r -d '' f; do
        name=$(basename "$f" | sed 's/\.[^.]*$//')
        thumb="$f"
        if [[ -x "$THUMB_BIN" ]]; then
          generated=$("$THUMB_BIN" "$f" 2>/dev/null)
          [[ -n "$generated" && -f "$generated" ]] && thumb="$generated"
        fi
        printf 'video\t%s\t%s\t%s\t%s\t%s\n' "$f" "$name" "$thumb" "$f" "$f"
      done
    ;;
  animated)
    # Animated/parallax art only: the user's own scenes. Theme backgrounds
    # belong to the image category (they are static jpgs/pngs).
    dirs=(
      "$HOME/.config/omarchy/animated"
      "$HOME/Wallpapers/Animated"
    )
    for dir in "${dirs[@]}"; do
      [[ -d "$dir" ]] || continue
      # Parallax backgrounds: a folder with layers/0-*.svg ... plus a static
      # jpg/png preview next to it (the EPS stock preview works great).
      find -L "$dir" -mindepth 2 -maxdepth 2 -type d -name layers -print0 2>/dev/null |
        while IFS= read -r -d '' layers; do
          bgdir=$(dirname "$layers")
          [[ -d "$bgdir" ]] || continue
          n=$(basename "$bgdir" | cut -c1-36)
          preview=""
          pf=$(find -L "$bgdir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' \) | head -1)
          [[ -n "$pf" ]] && preview="$pf"
          printf 'animated\t%s\t%s\t%s\t%s\t%s\n' "$bgdir" "$n" "$preview" "" "$bgdir"
        done
      find -L "$dir" -maxdepth 1 -type f \( -iname '*.gif' -o -iname '*.webp' -o -iname '*.apng' -o -iname '*.svg' \) -print0 2>/dev/null |
        sort -z | while IFS= read -r -d '' f; do
          name=$(basename "$f" | sed 's/\.[^.]*$//')
          preview="$f"
          media=""
          applied="$f"
          generated=$( "$(command -v omarchy-bg-anim2mp4 2>/dev/null || echo "$PLUGIN_DIR/omarchy-bg-anim2mp4")" "$f" 2>/dev/null)
          if [[ -n "$generated" && "$generated" == *.mp4 ]]; then
            media="$generated"
            applied="$generated"
            [[ -f "$generated.poster.jpg" ]] && preview="$generated.poster.jpg"
          elif [[ -n "$generated" && "$generated" == *.png ]]; then
            # static artwork (responsive SVG): no playable media; the
            # switcher gives the slice its motion with a parallax drift.
            preview="$generated"
            applied="$generated"
          fi
          printf 'animated\t%s\t%s\t%s\t%s\t%s\n' "$f" "$name" "$preview" "$media" "$applied"
        done
    done
    ;;
  audio)
    # The plugin's own curated effect list (state.json "effects") — what the
    # user sees in the audio-background panel. 14 are backed by the ttfx
    # engine; 6 (wave/bars/donut/fire/starfield/life) are native to the
    # audio-background wrapper.
    effects=(matrix rain wave bars donut fire starfield life \
             beams burn rings vhstape blackhole colorshift synthgrid \
             swarm bubbles fireworks thunderstorm spray)
    FX_PREVIEW_BIN="$(pick_bin omarchy-bg-fx-preview.sh)"
    cache="$HOME/.cache/omarchy/fx-previews"
    poster_dir="$HOME/Wallpapers/ASCII"
    mkdir -p "$poster_dir"
    for fx in "${effects[@]}"; do
      # Poster (static frame) lives in ~/Wallpapers/ASCII — used by the
      # switcher for every item that is NOT selected; the selected item
      # plays the LIVE preview from the fxlive daemon (Canvas), so the mp4
      # is only an optional extra: attach it when cached, but NEVER block
      # the list on rendering one — missing previews generate in the
      # background and show up on the next panel open/reload.
      preview="$poster_dir/$fx.jpg"; media=""
      # Shipped posters are the fallback for fresh installs (the switcher
      # still prefers the user's own ~/Wallpapers/ASCII copy when present).
      [[ -f "$preview" ]] || preview="$PLUGIN_DIR/../assets/posters/$fx.jpg"
      [[ -f "$cache/$fx.mp4" ]] && media="$cache/$fx.mp4"
      # wave/bars/donut/fire/starfield/life are NATIVE to the audio-background
      # wrapper, not ttfx effects — the mp4 recorder cannot render them (and
      # their posters ship pre-generated), so never queue a render for them.
      case "$fx" in wave|bars|donut|fire|starfield|life) native=1 ;; *) native=0 ;; esac
      if [[ -n "$FX_PREVIEW_BIN" && "$native" == 0 && ( ! -f "$preview" || -z "$media" ) ]]; then
        ("$FX_PREVIEW_BIN" "$fx" >/dev/null 2>&1 &)
      fi
      printf 'audio\t%s\t%s\t%s\t%s\t%s\n' "$fx" "$fx" "$preview" "$media" "$fx"
    done
    ;;
esac
