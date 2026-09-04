#!/usr/bin/env python3
"""Live ttfx effect previews for the background switcher (stdio protocol).

One instance is spawned by the switcher while open. The QML writes one JSON
command per line to our stdin and reads one JSON frame per line from stdout:

  in : {"cmd":"sub","id":N,"fx":"wave","cols":60,"rows":20}
  in : {"cmd":"unsub","id":N}
  out: {"id":N,"cells":"x,y,char,#rrggbb;...","w":60,"h":20}

Each subscribed effect runs the audio-background wrapper (--ttfx --audio 1) on
a private pty, so the little boxes show the REAL effect live and audio-reactive.
Only painted cells are sent (~2-6KB/frame, ~12fps/effect).
"""
import asyncio
import fcntl
import json
import os
import pty
import re
import struct
import subprocess
import sys
import termios
import time

WRAPPER = os.path.expanduser(
    "~/.config/omarchy/plugins/io.github.avillagran.omarchy-audio-background/"
    "bin/ttfx-bg-rs-live"
)
TTFX_CLI = os.path.expanduser(
    "~/.config/omarchy/plugins/io.github.avillagran.omarchy-audio-background/"
    "ttfx-src/target/release/ttfx"
)

NATIVE = {"wave", "bars", "donut", "fire", "starfield", "life",
          "starfield2", "wave2", "bars2", "vortex", "starorbit2",
          "mictrails2", "stardrift", "glitch", "spark", "flow"}
FRAME_BUDGET = 1.0 / 12

SGR_RE = re.compile(rb"\x1b\[([0-9;?]*)([a-zA-Z])")


def sgr_to_rgb(params):
    parts = [p for p in params.split(b";") if p != b""]
    try:
        nums = [int(p) for p in parts]
    except ValueError:
        return None
    if not nums:
        return (204, 204, 204)
    i = 0
    rgb = None
    while i < len(nums):
        n = nums[i]
        if n == 0:
            rgb = None
        elif n == 39:
            rgb = (204, 204, 204)
        elif 30 <= n <= 37:
            rgb = [(0,0,0),(205,49,49),(0,205,0),(205,205,0),
                   (0,0,238),(205,30,205),(0,205,205),(229,229,229)][n - 30]
        elif 90 <= n <= 97:
            rgb = [(127,127,127),(255,85,85),(85,255,85),(255,255,85),
                   (85,85,255),(255,85,255),(85,255,255),(255,255,255)][n - 90]
        elif n in (38, 48) and i + 1 < len(nums):
            mode = nums[i + 1]
            if mode == 2 and i + 4 < len(nums):
                rgb = (nums[i + 2], nums[i + 3], nums[i + 4])
                i += 4
            elif mode == 5 and i + 2 < len(nums):
                v = nums[i + 2]
                if v < 16:
                    rgb = [(0,0,0),(205,49,49),(0,205,0),(205,205,0),(0,0,238),
                           (205,30,205),(0,205,205),(229,229,229),
                           (127,127,127),(255,85,85),(85,255,85),(255,255,85),
                           (85,85,255),(255,85,255),(85,255,255),(255,255,255)][v]
                elif v < 232:
                    v -= 16
                    scale = [0, 95, 135, 175, 215, 255]
                    rgb = (scale[v // 36], scale[(v % 36) // 6], scale[v % 6])
                else:
                    g = 8 + (v - 232) * 10
                    rgb = (g, g, g)
                i += 2
        i += 1
    return rgb


def parse_frame(rows, cw):
    out = []
    for y, raw in enumerate(rows):
        x = 0
        fg = None
        pos = 0
        for m in SGR_RE.finditer(raw):
            for ch in raw[pos:m.start()].decode("utf-8", "replace"):
                if x >= cw:
                    break
                if ch not in ("\r", "\n"):
                    if ch != " " and fg is not None:
                        out.append("%d,%d,%s,#%02x%02x%02x" % (x, y, ch, *fg))
                    x += 1
            if m.group(2) == b"m":
                fg = sgr_to_rgb(m.group(1))
            pos = m.end()
        for ch in raw[pos:].decode("utf-8", "replace"):
            if x >= cw:
                break
            if ch not in ("\r", "\n"):
                if ch != " " and fg is not None:
                    out.append("%d,%d,%s,#%02x%02x%02x" % (x, y, ch, *fg))
                x += 1
    return ";".join(out)


class EffectSession:
    def __init__(self, fx, cols, rows):
        self.fx = fx
        self.cols = cols
        self.rows = rows
        self.proc = None
        self.master = None
        self.last_push = 0.0
        self.refs = 0
        self.start()

    def start(self):
        if self.fx in NATIVE or os.path.exists(WRAPPER):
            cmd = [WRAPPER, "--ttfx", "--effect", self.fx,
                   "--cols", str(self.cols), "--rows", str(self.rows),
                   "--ttfx-text", "OMARCHY", "--audio", "1"]
        else:
            cmd = [TTFX_CLI, "--input-file", "/dev/null",
                   "--canvas-width", str(self.cols),
                   "--canvas-height", str(self.rows),
                   "--anchor-canvas", "c", "--anchor-text", "c",
                   "--frame-rate", "15", self.fx]
        self.master, slave = pty.openpty()
        winsz = struct.pack("HHHH", self.rows + 8, self.cols + 8, 0, 0)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, winsz)
        self.proc = subprocess.Popen(
            cmd, stdin=slave, stdout=slave, stderr=slave,
            close_fds=True, start_new_session=True,
        )
        os.close(slave)
        os.set_blocking(self.master, False)

    def stop(self):
        try:
            if self.proc:
                self.proc.kill()
        except Exception:
            pass
        try:
            if self.master is not None:
                os.close(self.master)
        except Exception:
            pass

    def pump(self):
        buf = b""
        fd = self.master
        if fd is None:
            return None
        while True:
            try:
                chunk = os.read(fd, 262144)
            except (BlockingIOError, OSError):
                break
            if not chunk:
                break
            buf += chunk
            if len(buf) > 4 * 262144:
                break
        if not buf:
            return None
        frames = re.split(rb"\x1b\[\?1049h|\x1b\[H|\x1b8\x1b7\x1b\[\d+A", buf)
        last = None
        for fr in frames:
            rows = re.split(rb"\r\n|[\r\n]", fr)[: self.rows]
            if len(rows) >= self.rows:
                last = rows
        if last is None:
            return None
        now = time.time()
        if now - self.last_push < FRAME_BUDGET:
            return None
        self.last_push = now
        return parse_frame(last, self.cols)

    def alive(self):
        return self.proc is not None and self.proc.poll() is None


SESSIONS = {}
STDIN_BUF = b""


def handle_cmd(line):
    try:
        req = json.loads(line)
    except ValueError:
        return
    cmd = req.get("cmd")
    if cmd == "sub":
        fx = str(req["fx"])[:32]
        cols = min(max(int(req.get("cols", 60)), 10), 200)
        rows = min(max(int(req.get("rows", 20)), 8), 80)
        sess = SESSIONS.get(fx)
        if sess and (sess.cols != cols or sess.rows != rows):
            # resize requested (slice expanded): restart at the new grid
            sess.stop()
            del SESSIONS[fx]
            sess = None
        if sess is None:
            sess = EffectSession(fx, cols, rows)
            SESSIONS[fx] = sess
        sess.refs += 1
        print(json.dumps({"fx": fx, "cells": "", "w": cols, "h": rows}), flush=True)
    elif cmd == "unsub":
        fx = str(req["fx"])[:32]
        sess = SESSIONS.get(fx)
        if sess:
            sess.refs -= 1
            if sess.refs <= 0:
                sess.stop()
                del SESSIONS[fx]


async def main():
    loop = asyncio.get_running_loop()
    quit = asyncio.Event()

    def on_stdin():
        global STDIN_BUF
        try:
            data = os.read(0, 65536)
        except OSError:
            quit.set()
            return
        if not data:
            quit.set()
            return
        STDIN_BUF += data
        while b"\n" in STDIN_BUF:
            line, STDIN_BUF = STDIN_BUF.split(b"\n", 1)
            handle_cmd(line.decode("utf-8", "replace").strip())

    loop.add_reader(0, on_stdin)
    print("READY", flush=True)

    try:
        while not quit.is_set():
            await asyncio.sleep(0.04)
            for fx, sess in list(SESSIONS.items()):
                if not sess.alive():
                    # self-heal: respawn instead of dropping — clients hold no
                    # re-subscribe logic and would freeze on a silent loss
                    try:
                        sess.stop()
                        sess.start()
                    except Exception:
                        del SESSIONS[fx]
                    continue
                cells = sess.pump()
                if cells is None:
                    continue
                print(json.dumps({"fx": fx, "cells": cells,
                                  "w": sess.cols, "h": sess.rows}), flush=True)
    finally:
        for sess in SESSIONS.values():
            sess.stop()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        for sess in SESSIONS.values():
            sess.stop()
