#!/usr/bin/env python3
"""Capture a ttfx effect stream through a pty with a forced window size.

ttfx sizes and anchors its canvas against the tty dimensions, so the pty must
be at least as tall as the canvas or frames come out truncated. script(1)
inherits whatever size its own controlling tty has — use an explicit pty
instead and set TIOCSWINSZ ourselves.

Usage: fxcapture.py <out-stream> <cols> <rows> <timeout-secs> -- <ttfx-cmd...>
"""
import fcntl
import os
import pty
import select
import struct
import subprocess
import sys
import termios
import time


def main():
    out_path = sys.argv[1]
    cols = int(sys.argv[2])
    rows = int(sys.argv[3])
    timeout_s = float(sys.argv[4])
    cmd = sys.argv[sys.argv.index("--") + 1:]

    master, slave = pty.openpty()
    # window big enough for the canvas: a couple of rows of slack for the
    # centered anchor math, generous cols for the 96-wide canvas
    winsz = struct.pack("HHHH", max(rows + 8, 24), max(cols + 8, 120), 0, 0)
    fcntl.ioctl(slave, termios.TIOCSWINSZ, winsz)

    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave,
        close_fds=True, start_new_session=True,
    )
    os.close(slave)

    deadline = time.time() + timeout_s
    chunks = []
    with open(out_path, "wb") as out:
        while time.time() < deadline:
            r, _, _ = select.select([master], [], [], 0.25)
            if master in r:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break  # pty closed (effect exited)
                if not data:
                    break
                out.write(data)
            if proc.poll() is not None and not r:
                break
    try:
        proc.terminate()
        proc.wait(timeout=2)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass
    os.close(master)


if __name__ == "__main__":
    main()
