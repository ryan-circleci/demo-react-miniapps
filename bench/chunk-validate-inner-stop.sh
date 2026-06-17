#!/usr/bin/env bash
# Inner-arm Stop hook: validate on sidecar, then block stop until commit + push.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [[ "$(basename "$SCRIPT_DIR")" == "results" ]]; then
  ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  PTY="$SCRIPT_DIR/.chunk-validate-pty.sh"
else
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  PTY="$SCRIPT_DIR/chunk-validate-pty.sh"
fi
cd "$ROOT"

if ! bash "$PTY"; then
  exit 1
fi

if ! git diff --quiet HEAD || ! git diff --cached --quiet; then
  echo "Sidecar validation passed. Commit your changes, then end your turn again."
  exit 1
fi

AHEAD="$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)"
if [[ "$AHEAD" -lt 1 ]]; then
  echo "Sidecar validation passed and changes are committed. git push now, then end your turn."
  exit 1
fi

exit 0
