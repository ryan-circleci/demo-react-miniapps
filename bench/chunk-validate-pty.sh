#!/usr/bin/env bash
# Run chunk validate with a pseudo-TTY. chunk 0.7.79 deadlocks when stdout is
# piped (CI logs, agent shells). Treats chunk error output as failure even when
# the parent process exits 0, and drains the PTY until idle so late failures are
# never missed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${BENCH_REPO_ROOT:-}" ]]; then
  ROOT="$BENCH_REPO_ROOT"
elif [[ "$(basename "$SCRIPT_DIR")" == "results" ]]; then
  ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
else
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
cd "$ROOT"

if [[ ! -f .chunk/config.json ]]; then
  echo "ERROR: .chunk/config.json missing (cwd: $ROOT)" >&2
  exit 1
fi

export BENCH_REPO_ROOT="$ROOT"
exec python3 -u - "$ROOT" <<'PY'
import os
import pty
import re
import select
import sys
import time

ROOT = sys.argv[1]
os.chdir(ROOT)

FAILURE_PATTERNS = [
    "✗ Error",
    "No validate commands configured",
    re.compile(r"failed with exit code [1-9]"),
    re.compile(r"Test Suites: [1-9]\d* failed"),
    re.compile(r"Tests:\s+[1-9]\d* failed"),
    re.compile(r"^FAIL __tests__/", re.M),
]
GATE_RAN_PATTERNS = [
    "running on sidecar",
    "Running install-payments",
    "Running lint-payments",
]

def failed(text: str) -> bool:
    for pat in FAILURE_PATTERNS:
        if isinstance(pat, str):
            if pat in text:
                return True
        elif pat.search(text):
            return True
    return False

def gates_ran(text: str) -> bool:
    return any(p in text for p in GATE_RAN_PATTERNS)

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
    sys.exit(127)

os.close(slave)
buf = bytearray()
child_done = False
status = 0
idle_after_exit = 0.0
DRAIN_IDLE_SEC = 2.0
SELECT_SEC = 0.25

while True:
    if child_done and idle_after_exit >= DRAIN_IDLE_SEC:
        break
    timeout = SELECT_SEC if child_done else 1.0
    r, _, _ = select.select([master], [], [], timeout)
    if master in r:
        try:
            data = os.read(master, 65536)
        except OSError:
            data = b""
        if data:
            buf.extend(data)
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
            idle_after_exit = 0.0
        elif child_done:
            idle_after_exit += timeout
    elif child_done:
        idle_after_exit += timeout

    if not child_done:
        wp, st = os.waitpid(pid, os.WNOHANG)
        if wp == pid:
            child_done = True
            status = st
            idle_after_exit = 0.0

if not child_done:
    _, status = os.waitpid(pid, 0)

try:
    os.close(master)
except OSError:
    pass

text = buf.decode("utf-8", errors="replace")
code = os.waitstatus_to_exitcode(status)

if failed(text):
    sys.exit(code if code != 0 else 1)
if code != 0:
    sys.exit(code)
if not gates_ran(text):
    print("ERROR: chunk validate produced no sidecar gate output", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
