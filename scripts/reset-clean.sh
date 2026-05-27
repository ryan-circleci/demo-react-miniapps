#!/usr/bin/env bash
#
# reset-clean.sh — restore the demo files to the clean, green baseline.
#
# Restores only the file(s) the demo touches, so any unrelated work in the
# working tree is preserved.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

git checkout HEAD -- miniapps/payments/src/App.js miniapps/payments/__tests__/App.test.js

echo "Reset miniapps/payments/{src/App.js,__tests__/App.test.js} to HEAD."
echo ""
echo "Run 'chunk validate' to confirm green baseline before next demo run."
