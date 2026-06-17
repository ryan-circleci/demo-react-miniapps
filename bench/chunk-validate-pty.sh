#!/usr/bin/env bash
# Run chunk validate with a pseudo-TTY. chunk 0.7.79 deadlocks when stdout is
# piped (CI logs, agent shells). Also treats chunk error output as failure even
# when the process exits 0.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 -u <<'PY'
import os, pty, select, sys

master, slave = pty.openpty()
pid = os.fork()
if pid == 0:
    os.close(master)
    os.setsid()
    os.dup2(slave, 0)
    os.dup2(slave, 1)
    os.dup2(slave, 2)
    os.close(slave)
    os.execvp("chunk", ["chunk", "validate"])
else:
    os.close(slave)
    buf = bytearray()
    while True:
        r, _, _ = select.select([master], [], [], 1.0)
        if master in r:
            try:
                data = os.read(master, 4096)
            except OSError:
                break
            if not data:
                break
            buf.extend(data)
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
        wp, status = os.waitpid(pid, os.WNOHANG)
        if wp == pid:
            while True:
                r, _, _ = select.select([master], [], [], 0)
                if master not in r:
                    break
                data = os.read(master, 4096)
                if not data:
                    break
                buf.extend(data)
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()
            text = buf.decode("utf-8", errors="replace")
            code = os.waitstatus_to_exitcode(status)
            if code != 0:
                sys.exit(code)
            if "✗ Error" in text or "failed with exit code" in text:
                sys.exit(1)
            sys.exit(0)
PY
