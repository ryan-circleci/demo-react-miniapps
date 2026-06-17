#!/usr/bin/env bash
# validate-log-check.sh LOG_FILE
# Exit 0 if the log shows a full successful sidecar gate run; non-zero otherwise.
# Used by run-trial.sh as a belt-and-suspenders check on top of the PTY wrapper.
set -euo pipefail
LOG="${1:?usage: validate-log-check.sh <log>}"
[[ -f "$LOG" ]] || { echo "missing log: $LOG" >&2; exit 1; }

if rg -q 'No validate commands configured|✗ Error' "$LOG"; then
  echo "validate log contains chunk error markers" >&2
  exit 1
fi
if rg -q 'failed with exit code [1-9]' "$LOG"; then
  echo "validate log contains remote gate failure" >&2
  exit 1
fi
if rg -q 'Test Suites: [1-9][0-9]* failed|Tests:[[:space:]]+[1-9][0-9]* failed|^FAIL __tests__/' "$LOG"; then
  echo "validate log contains test failure" >&2
  exit 1
fi
if ! rg -q 'running on sidecar|Running install-payments' "$LOG"; then
  echo "validate log missing sidecar gate output" >&2
  exit 1
fi
exit 0
