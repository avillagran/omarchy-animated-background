#!/usr/bin/env bash
# One-command installer for the animated, audio, and Amiga backgrounds.
# Usage: curl -fsSL https://raw.githubusercontent.com/avillagran/omarchy-animated-background/main/install.sh | bash
set -euo pipefail

ANIMATED_REPO="https://github.com/avillagran/omarchy-animated-background"
AUDIO_REPO="https://github.com/avillagran/omarchy-audio-background"
AMIGA_REPO="https://github.com/avillagran/omarchy-amiga"
WALLPAPERS_URL="https://github.com/avillagran/omarchy-animated-background/releases/download/samplepack-v1/omarchy-wallpapers-samplepack.zip"
AMIGA_PACK_URL="https://github.com/avillagran/omarchy-animated-background/releases/download/amiga-pack-v0.1/omarchy-amiga-demos-v0.1.zip"
ANIMATED_ID="io.github.avillagran.omarchy-animated-backgrounds"
AUDIO_ID="io.github.avillagran.omarchy-audio-background"
AMIGA_ID="io.github.avillagran.omarchy-amiga"

log() { printf '[omarchy-backgrounds] %s\n' "$*"; }
fail() { printf '[omarchy-backgrounds] error: %s\n' "$*" >&2; exit 1; }

ACTION="${1:-install}"
case "$ACTION" in
  install|--install) ;;
  --uninstall) ;;
  -h|--help)
    printf '%s\n' \
      'Usage: install.sh [--uninstall]' \
      '  (default)       Install and enable all background plugins and sample content.' \
      '  --uninstall     Remove the plugins and selector bind, but keep all user media.'
    exit 0
    ;;
  *) fail "unknown option: $ACTION" ;;
esac

command -v omarchy >/dev/null 2>&1 || fail "omarchy command not found; run this on Omarchy."
command -v omarchy-shell >/dev/null 2>&1 || fail "omarchy-shell command not found."
if [[ "$ACTION" != --uninstall ]]; then
  command -v curl >/dev/null 2>&1 || fail "curl is required."
  command -v unzip >/dev/null 2>&1 || fail "unzip is required."
fi

uninstall_plugin() {
  local id="$1" manifest="$HOME/.config/omarchy/plugins/$1/manifest.json"
  if [[ -f "$manifest" ]]; then
    log "Removing plugin: $id"
    omarchy plugin remove "$id" --yes || log "Could not remove $id through Omarchy; leaving it untouched"
  else
    log "Plugin not installed, skipping: $id"
  fi
}

uninstall_bind() {
  local hypr_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
  local target="$hypr_dir/hypr/parallax-backgrounds.lua"
  local main="$hypr_dir/hyprland.lua"
  local source="$HOME/.config/omarchy/plugins/$ANIMATED_ID/hypr/parallax-backgrounds.lua"

  if [[ -f "$target" && -f "$source" ]] && cmp -s "$source" "$target"; then
    rm -f "$target"
    log "Removed the background selector takeover bind"
  elif [[ -f "$target" ]]; then
    log "Keeping modified selector bind file: $target"
  fi
  if [[ -f "$main" ]]; then
    sed -i '\|require("hypr\.parallax-backgrounds")|d' "$main"
  fi
  hyprctl reload >/dev/null 2>&1 || true
}

if [[ "$ACTION" == --uninstall ]]; then
  AMIGA_LAUNCHER="$HOME/.config/omarchy/plugins/$AMIGA_ID/bin/omarchy-amiga"
  if [[ -x "$AMIGA_LAUNCHER" ]]; then
    "$AMIGA_LAUNCHER" stop >/dev/null 2>&1 || true
  fi
  uninstall_bind
  uninstall_plugin "$ANIMATED_ID"
  uninstall_plugin "$AMIGA_ID"
  uninstall_plugin "$AUDIO_ID"
  log "Uninstall complete; user wallpapers and Amiga media were kept"
  exit 0
fi

install_plugin() {
  local repo="$1" id="$2" manifest
  manifest="$HOME/.config/omarchy/plugins/$id/manifest.json"
  if [[ -f "$manifest" ]]; then
    log "Plugin already installed: $id"
    omarchy plugin enable "$id" >/dev/null 2>&1 || true
    return 0
  fi
  log "Installing and enabling $repo"
  if ! omarchy plugin add "$repo" --enable --yes; then
    # The clone may have completed while the shell was restarting. Continue
    # only when the manifest proves that the plugin was actually installed.
    [[ -f "$manifest" ]] || fail "Could not install plugin: $repo"
    log "Plugin was installed while Omarchy shell was restarting: $id"
  fi
}

# Install the companion first so ASCII/AUDIO can render immediately.
install_plugin "$AUDIO_REPO" "$AUDIO_ID"
install_plugin "$AMIGA_REPO" "$AMIGA_ID"
install_plugin "$ANIMATED_REPO" "$ANIMATED_ID"

# FS-UAE is installed by the Amiga plugin and the command is safe to repeat.
AMIGA_INSTALL="$HOME/.config/omarchy/plugins/$AMIGA_ID/bin/omarchy-amiga-install"
if [[ -x "$AMIGA_INSTALL" ]]; then
  log "Installing FS-UAE and Amiga runtime dependencies"
  "$AMIGA_INSTALL" --install-deps
else
  fail "Amiga plugin installed but its installer was not found: $AMIGA_INSTALL"
fi

# Download the sample content from GitHub releases. These archives are kept
# outside the plugin source repository.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log "Downloading sample wallpapers"
curl -fL --retry 3 --retry-delay 2 -o "$TMP_DIR/wallpapers.zip" "$WALLPAPERS_URL"
unzip -qo "$TMP_DIR/wallpapers.zip" -d "$TMP_DIR/wallpapers"
WALLPAPERS_ROOT="$(find "$TMP_DIR/wallpapers" -type d -name Wallpapers -print -quit)"
[[ -n "$WALLPAPERS_ROOT" ]] || fail "wallpaper archive has no Wallpapers directory"
mkdir -p "$HOME/Wallpapers"
cp -a "$WALLPAPERS_ROOT/." "$HOME/Wallpapers/"

log "Downloading Amiga demo pack v0.1"
mkdir -p "$HOME/Wallpapers/Amiga"
curl -fL --retry 3 --retry-delay 2 -o "$TMP_DIR/amiga.zip" "$AMIGA_PACK_URL"
unzip -qo "$TMP_DIR/amiga.zip" -d "$HOME/Wallpapers/Amiga"

GENERATE="$HOME/.config/omarchy/plugins/$AMIGA_ID/bin/omarchy-amiga-generate-fsuae"
if [[ -x "$GENERATE" ]]; then
  log "Generating local FS-UAE configs for Amiga demos"
  "$GENERATE" "$HOME/Wallpapers/Amiga" --force
fi

# Ensure newly installed plugin manifests are visible before invoking helpers.
log "Refreshing Omarchy plugins"
shell_ready=0
for _ in {1..12}; do
  if omarchy-shell shell rescanPlugins >/dev/null 2>&1; then
    shell_ready=1
    break
  fi
  log "Waiting for Omarchy shell to recover ($_/12)"
  sleep 2
done
[[ "$shell_ready" == 1 ]] || fail "Omarchy shell did not recover after 24 seconds"

for id in "$AUDIO_ID" "$AMIGA_ID" "$ANIMATED_ID"; do
  omarchy plugin enable "$id" >/dev/null 2>&1 || true
done

KEYBIND="$HOME/.config/omarchy/plugins/$ANIMATED_ID/bin/omarchy-parallax-keybind"
if [[ -x "$KEYBIND" ]]; then
  log "Binding Ctrl+Super+Space to the background selector"
  "$KEYBIND"
else
  fail "Animated background plugin installed but its keybind helper was not found: $KEYBIND"
fi

log "Installation complete"
log "Press Ctrl+Super+Space to open the background selector."
log "Use S for shuffle (Videos, Amiga, ASCII) and L/M in the Amiga category."
