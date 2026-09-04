# omarchy-animated-backgrounds

Mouse-parallax, multi-source backgrounds for [Omarchy](https://omarchy.org) —
as a **plugin**. This is the plugin edition of the parallax-background work
proposed to Omarchy as a shell PR; installing the plugin gives you the same
system on a **stock Omarchy** install, no shell patches required.

The plugin renders its own background layer (image, video, animated, and
layered parallax scenes) above the regular wallpaper, and ships a background
switcher with live previews.

## Features

- **Layered parallax scenes** — a scene is a folder: `layers/0-*.svg … N-*.svg`
  stacked back → front, each drifting with mouse depth (`+` / `-` sets the
  strength 1–8 in the switcher, `space` toggles the drift). Optional
  `parallax.json` overrides per-layer factors; a `poster.jpg` next to the
  layers is the static fallback/preview.
- **Animated sources** — `gif`/`webp`/`apng` are converted once to a cached
  looping `mp4`; static/responsive `svg` artwork gets the parallax drift.
- **Videos** and plain **images**, with crossfade transitions.
- **ASCII/AUDIO category** — live effect previews in the switcher (install the
  companion [omarchy-audio-background](https://github.com/avillagran/omarchy-audio-background)
  plugin to also run them as real desktop backgrounds).
- **Live background switcher** — skewed-carousel picker, instant static
  posters under live media previews, live dir watching (drop a file in and it
  appears), selection restore on cancel.
- Bar text color keeps working: the plugin keeps the canonical
  `~/.local/state/omarchy/current/background` symlink pointing at the real
  media, which Omarchy's `omarchy-bar-text-color` already samples.

## Install

```sh
# 1. Plugin (classic install: clone + enable)
omarchy plugin add https://github.com/avillagran/omarchy-animated-backgrounds --enable --yes

# 2. Sample content — 11 videos + 2 ready-made parallax scenes
#    (skip if you already have your own ~/Wallpapers content)
curl -sL -o /tmp/omarchy-wallpapers.zip \
  https://github.com/avillagran/omarchy-animated-backgrounds/releases/download/samplepack-v1/omarchy-wallpapers-samplepack.zip \
  && unzip -qo /tmp/omarchy-wallpapers.zip -d /tmp \
  && cp -r /tmp/omarchy-wallpapers-samplepack/Wallpapers ~/ \
  && rm -rf /tmp/omarchy-wallpapers.zip /tmp/omarchy-wallpapers-samplepack

# 3. Open the switcher once (or bind it — see below)
omarchy-shell io.github.avillagran.omarchy-animated-backgrounds toggle
```

Add a keybind to open/close the switcher (e.g. in your Hyprland user
config / sensei binds):

```
bind = SUPER, B, exec, omarchy-shell -q io.github.avillagran.omarchy-animated-backgrounds toggle
```

> **Bind takeover:** on first load the plugin takes over Omarchy's stock
> `SUPER + CTRL + SPACE` (which opens the built-in background chooser) and
> points it at this plugin's switcher instead. It does so by installing
> `~/.config/hypr/hypr/parallax-backgrounds.lua` and adding one
> `require("hypr.parallax-backgrounds")` line to `~/.config/hypr/hyprland.lua`
> (idempotent, reapplied on every plugin load).
> **Opt out:** delete that require line and run `hyprctl reload` — the stock
> chooser bind returns.

Or from a terminal:

```sh
omarchy-shell -q io.github.avillagran.omarchy-animated-backgrounds toggle
```

## Where your content goes

> **Just want to try it?** Grab the
> [sample wallpapers pack](https://github.com/avillagran/omarchy-animated-backgrounds/releases/tag/samplepack-v1)
> (11 videos + 2 parallax scenes) and unzip it into your home directory —
> the switcher picks the files up live.

```
~/Wallpapers/Images/    still images (jpg/png/webp/bmp; theme wallpapers also listed)
~/Wallpapers/Videos/    videos (mp4/mkv/mov/webm/avi)
~/Wallpapers/Animated/  gif/webp/apng/svg files AND parallax scene directories
```

A **parallax scene** is a directory in `~/Wallpapers/Animated/`:

```
my-scene/
  layers/
    0-sky.svg        # back layer (any raster works inside the wrapper)
    1-hills.svg
    2-trees.svg      # front layer
  parallax.json      # optional: {"layers": {"0-sky": 0.0, "1-hills": 0.4, "2-trees": 1.0}}
  poster.jpg         # optional: static preview / fallback
```

Layer order is the numeric prefix (0 = back). Factor `0.0` = static,
`1.0` = full mouse drift. Default is linear depth (`i/(N-1)`).

## Switcher keys

| Key | Action |
| --- | --- |
| `←` `→` / `Tab` `Shift+Tab` | move between items |
| `↑` `↓` | switch category |
| `Enter` | apply |
| `Space` | toggle parallax movement |
| `+` / `-` | parallax resolution 1–8 (default 2) |
| `Esc` | cancel (restores the previous background) |

Double-clicking the desktop still opens Omarchy's regular wallpaper/theme
switchers as usual.

## Notes & limitations

- The stock Omarchy wallpaper keeps rendering underneath; this plugin draws
  its own layer on top of it. Selecting a background here does **not** change
  Omarchy's own wallpaper setting.
- Live ASCII **backgrounds** (not just previews) need the companion
  `omarchy-audio-background` plugin; without it the ASCII category still
  previews natively-rendered effects and applies show a transparent
  background.
- Regenerating ASCII preview videos (optional) needs `ttfx` on PATH
  (`TTFX_BIN` overrides). All 20 effect posters ship with the plugin.

## Local development

```sh
ln -sfn "$PWD" ~/.config/omarchy/plugins/io.github.avillagran.omarchy-animated-backgrounds
omarchy-shell shell rescanPlugins
omarchy-restart-shell
```

## License

MIT
