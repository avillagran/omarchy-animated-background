#!/usr/bin/env bash
# One-command installer for the animated, audio, and Amiga backgrounds.
# Usage: curl -fsSL https://raw.githubusercontent.com/avillagran/omarchy-animated-background/main/install.sh | bash
set -euo pipefail

ANIMATED_REPO="https://github.com/avillagran/omarchy-animated-background"
AUDIO_REPO="https://github.com/avillagran/omarchy-audio-background"
AMIGA_REPO="https://github.com/avillagran/omarchy-amiga"
ANIMATED_ID="io.github.avillagran.omarchy-animated-backgrounds"
AMIGA_ID="io.github.avillagran.omarchy-amiga"

log() { printf '[omarchy-backgrounds] %s\n' "$*"; }
fail() { printf '[omarchy-backgrounds] error: %s\n' "$*" >&2; exit 1; }

command -v omarchy >/dev/null 2>&1 || fail "omarchy command not found; run this on Omarchy."
command -v omarchy-shell >/dev/null 2>&1 || fail "omarchy-shell command not found."

install_plugin() {
  local repo="$1"
  log "Installing and enabling $repo"
  omarchy plugin add "$repo" --enable --yes
}

# Install the companion first so ASCII/AUDIO can render immediately.
install_plugin "$AUDIO_REPO"
install_plugin "$AMIGA_REPO"
install_plugin "$ANIMATED_REPO"

# FS-UAE is installed by the Amiga plugin and the command is safe to repeat.
AMIGA_INSTALL="$HOME/.config/omarchy/plugins/$AMIGA_ID/bin/omarchy-amiga-install"
if [[ -x "$AMIGA_INSTALL" ]]; then
  log "Installing FS-UAE and Amiga runtime dependencies"
  "$AMIGA_INSTALL" --install-deps
else
  fail "Amiga plugin installed but its installer was not found: $AMIGA_INSTALL"
fi

# Ensure newly installed plugin manifests are visible before invoking helpers.
log "Refreshing Omarchy plugins"
omarchy-shell shell rescanPlugins || true

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
