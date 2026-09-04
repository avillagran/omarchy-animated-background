#!/usr/bin/env python3
"""Render a captured ttfx ANSI stream into per-frame PNGs.

The stream is a concatenation of full-canvas repaints: canvas_height lines of
canvas_width cells per frame, SGR colors inline, lines terminated by CR/LF.
No cursor movement sequences are used (full repaint mode).

Usage: fxrender.py <ansi-file> <out-dir> <canvas-width> <canvas-height> [max-frames]
"""
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

CELL_W = 8
CELL_H = 14

X256 = []
for i in range(16):
    X256.append(None)  # filled below
X256[0] = (0, 0, 0); X256[1] = (128, 0, 0); X256[2] = (0, 128, 0); X256[3] = (128, 128, 0)
X256[4] = (0, 0, 128); X256[5] = (128, 0, 128); X256[6] = (0, 128, 128); X256[7] = (192, 192, 192)
X256[8] = (128, 128, 128); X256[9] = (255, 0, 0); X256[10] = (0, 255, 0); X256[11] = (255, 255, 0)
X256[12] = (0, 0, 255); X256[13] = (255, 0, 255); X256[14] = (0, 255, 255); X256[15] = (255, 255, 255)
_steps = [0, 95, 135, 175, 215, 255]
for r in _steps:
    for g in _steps:
        for b in _steps:
            X256.append((r, g, b))
for i in range(24):
    v = 8 + i * 10
    X256.append((v, v, v))


def parse_sgr(params, fg, bg):
    i = 0
    while i < len(params):
        p = params[i]
        if p in (0,):
            fg, bg = None, None
        elif p == 39:
            fg = None
        elif p == 49:
            bg = None
        elif 30 <= p <= 37:
            fg = X256[p - 30]
        elif 90 <= p <= 97:
            fg = X256[p - 90 + 8]
        elif 40 <= p <= 47:
            bg = X256[p - 40]
        elif 100 <= p <= 107:
            bg = X256[p - 100 + 8]
        elif p == 38 and i + 1 < len(params):
            mode = params[i + 1]
            if mode == 5 and i + 2 < len(params):
                fg = X256[params[i + 2] % 256]; i += 2
            elif mode == 2 and i + 4 < len(params):
                fg = tuple(params[i + 2:i + 5]); i += 4
        elif p == 48 and i + 1 < len(params):
            mode = params[i + 1]
            if mode == 5 and i + 2 < len(params):
                bg = X256[params[i + 2] % 256]; i += 2
            elif mode == 2 and i + 4 < len(params):
                bg = tuple(params[i + 2:i + 5]); i += 4
        i += 1
    return fg, bg


def parse_line(raw):
    """Return list of (text, fg, bg) runs for one raw line (bytes without CR/LF)."""
    runs = []
    fg = bg = None
    pos = 0
    for m in re.finditer(rb'\x1b\[([0-9;?]*)([a-zA-Z])', raw):
        if m.start() > pos:
            runs.append((raw[pos:m.start()].decode('utf-8', 'replace'), fg, bg))
        params_s = m.group(1).decode()
        cmd = m.group(2).decode()
        if cmd == 'm':
            params = [int(x) if x else 0 for x in params_s.split(';')] if params_s else [0]
            fg, bg = parse_sgr(params, fg, bg)
        # other sequences (smkx etc.) carry no visible cell data
        pos = m.end()
    if pos < len(raw):
        runs.append((raw[pos:].decode('utf-8', 'replace'), fg, bg))
    return runs


def main():
    stream_path, out_dir, cw, ch = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    max_frames = int(sys.argv[5]) if len(sys.argv) > 5 else 10**9
    os.makedirs(out_dir, exist_ok=True)

    # Noto Sans Mono CJK JP: covers latin + halfwidth katakana that several
    # effects (matrix, rain...) use — Liberation Mono renders those as tofu.
    font = ImageFont.truetype('/usr/share/fonts/noto-cjk/NotoSansCJK-Bold.ttc', 14, index=5)

    raw = open(stream_path, 'rb').read()
    # ttfx delimits frames with restore+save-cursor + cursor-up-home:
    #   ESC 8 ESC 7 ESC [<n>A
    # <n> depends on the terminal height and the canvas anchor (e.g. centered
    # canvases sit mid-window), so match any count. Splitting on the fixed
    # ESC 8 ESC 7 prefix keeps the canvas-height alignment unambiguous.
    marker_re = re.compile(rb'\x1b8\x1b7\x1b\[\d+A')
    chunks = marker_re.split(raw)[1:]
    if not chunks:
        # wrapper-native effects (wave/bars/donut/fire/starfield/life) repaint
        # via plain cursor-home: ESC [ H + full rows. Alternate screen start
        # (ESC [ ?1049h) also acts as a frame boundary.
        home_re = re.compile(rb'\x1b\[\?1049h|\x1b\[H')
        chunks = home_re.split(raw)[1:]
    frames = []
    for chunk in chunks:
        rows = re.split(rb'\r\n|[\r\n]', chunk)[:ch]
        if len(rows) < ch:
            continue
        frames.append(rows)
        if len(frames) >= max_frames:
            break

    W, H = cw * CELL_W, ch * CELL_H
    n = 0
    best_score = -1
    best_img = None
    last_good = -1
    first_good = -1
    for rows in frames:
        img = Image.new('RGB', (W, H), (7, 7, 13))
        draw = ImageDraw.Draw(img)
        colors = set()
        colored = 0
        for y, rawline in enumerate(rows):
            x = 0
            for text, fg, bg in parse_line(rawline):
                for chch in text:
                    if x >= cw:
                        break
                    px, py = x * CELL_W, y * CELL_H
                    if bg is not None:
                        draw.rectangle([px, py, px + CELL_W - 1, py + CELL_H - 1], fill=bg)
                        colors.add(bg)
                    if chch != ' ':
                        draw.text((px, py - 2), chch, font=font, fill=fg or (204, 204, 204))
                        if fg is not None:
                            colors.add(fg)
                            colored += 1
                    x += 1
        img.save(os.path.join(out_dir, 'f%04d.png' % n))
        # poster score: color variety peaks mid-effect (explosions, gradients);
        # a plain char count would pick the settled, static final frame.
        # Only VISIBLE glyphs count — tinted empty cells (effect intro/outro
        # paints spaces with dark SGR colors) must not inflate the score.
        visible = sum(1 for y, rawline in enumerate(rows) for text, fg, bg in parse_line(rawline) for chch in text if chch != ' ')
        score = len(colors) * 10 + visible
        if score > best_score:
            best_score = score
            best_img = img
        # tte effects end by clearing the canvas before exiting — the wrapper
        # loops them, but the CLI does not. Track the developed span so the
        # caller can cut intro/outro blackness. "Developed" = real glyphs on
        # canvas (tinted blank cells from cursor-wide SGR passes don't count).
        if visible > 2:
            if first_good < 0:
                first_good = n
            last_good = n
        n += 1
    if best_img is not None:
        best_img.save(os.path.join(out_dir, 'best.png'))
    with open(os.path.join(out_dir, 'lastgood.txt'), 'w') as fh:
        fg = first_good if first_good >= 0 else 0
        lg = last_good if last_good >= 0 else n - 1
        fh.write('%d %d' % (fg, lg))
    print('frames:', n)


if __name__ == '__main__':
    main()
