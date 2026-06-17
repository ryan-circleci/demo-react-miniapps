#!/usr/bin/env bash
# Sync working tree to sidecar and run full gate set (PTY-wrapped chunk validate).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$(basename "$SCRIPT_DIR")" == "results" ]]; then
  ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  PTY="$SCRIPT_DIR/.chunk-validate-pty.sh"
else
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  PTY="$SCRIPT_DIR/chunk-validate-pty.sh"
fi
cd "$ROOT"
chunk sidecar sync
exec bash "$PTY"
