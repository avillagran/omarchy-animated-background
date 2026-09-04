#!/bin/bash
# Generate a thumbnail for a video file, caching it under
# ~/.cache/omarchy/background-switcher/thumbs.

VIDEO_PATH="$1"
[[ -z "$VIDEO_PATH" ]] && exit 1
[[ -f "$VIDEO_PATH" ]] || exit 1

CACHE_DIR="$HOME/.cache/omarchy/background-switcher/thumbs"
mkdir -p "$CACHE_DIR"

HASH=$(printf '%s' "$VIDEO_PATH" | md5sum | cut -d ' ' -f 1)
THUMB="$CACHE_DIR/$HASH.jpg"

if [[ ! -f "$THUMB" ]]; then
  ffmpeg -y -i "$VIDEO_PATH" -ss 00:00:01 -vframes 1 -q:v 2 -vf "scale=768:-1" "$THUMB" >/dev/null 2>&1 || exit 1
fi

printf '%s\n' "$THUMB"
