#!/usr/bin/env bash
#
# run-bench.sh [N] [phase]
#   N     = trials per arm (default 5)
#   phase = 1 (default) | 2  — or set BENCH_PHASE=2
#
# Orchestrates the full inner-vs-outer benchmark: N trials per arm, interleaved
# (inner-1, outer-1, inner-2, outer-2, ...) to spread out time-of-day API
# variance. Each trial runs on its own throwaway branch bench/<arm>-<trial>.
#
# Preconditions (checked below):
#   - OTEL stack up:        docker compose -f bench/docker-compose.yml up -d
#   - chunk sidecar up:     chunk sidecar current   (needed by the inner arm)
#   - clean working tree:   no uncommitted TRACKED changes (run-trial hard-resets)
#   - CircleCI token:       $CIRCLE_TOKEN (or $CIRCLECI_TOKEN) for CI-minute collection
set -euo pipefail

N="${1:-5}"
BENCH_PHASE="${BENCH_PHASE:-${2:-1}}"
export BENCH_PHASE
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BENCH_DIR/.." && pwd)"
cd "$REPO_ROOT"

fail() { echo "PREFLIGHT FAILED: $*" >&2; exit 1; }

echo "=== preflight ==="
# 1. observability stack
curl -fsS -o /dev/null http://localhost:9091/-/healthy 2>/dev/null || fail "pushgateway down — run: docker compose -f bench/docker-compose.yml up -d"
curl -fsS -o /dev/null http://localhost:9090/-/ready   2>/dev/null || fail "prometheus down — run: docker compose -f bench/docker-compose.yml up -d"
# 2. sidecar (inner arm needs it)
chunk sidecar current >/dev/null 2>&1 || fail "no active chunk sidecar — run: chunk sidecar current / create one"
# 3. clean tracked tree — run-trial hard-resets, which would destroy uncommitted work
DIRTY="$(git status --porcelain --untracked-files=no)"
[[ -z "$DIRTY" ]] || fail "uncommitted tracked changes present; commit/stash first:\n$DIRTY"
# 4. CI token (warn only — collection can be re-run later)
[[ -n "${CIRCLE_TOKEN:-${CIRCLECI_TOKEN:-}}" ]] || echo "WARN: no CIRCLE_TOKEN — CI-minute collection will be skipped (re-run collect-ci.mjs later)"

START_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
git config push.autoSetupRemote true   # so the agent's bare `git push` works on a new branch

echo "=== building bench base (phase ${BENCH_PHASE}; reduced gate set: Snyk dropped) ==="
bash "$BENCH_DIR/scenario/make-base.sh"
if [[ "$BENCH_PHASE" == "2" ]]; then
  bash "$BENCH_DIR/scenario/make-base-phase2.sh"
  export BENCH_BASE_REF=bench/base-phase2
else
  export BENCH_BASE_REF=bench/base
fi

cleanup() {
  cp "$BENCH_DIR/env/settings-inner.json" "$REPO_ROOT/.claude/settings.json" 2>/dev/null || true
  git checkout -q "$START_BRANCH" 2>/dev/null || true
  git checkout -q -- .claude/settings.json 2>/dev/null || true
  echo "=== restored branch $START_BRANCH and settings ==="
}
trap cleanup EXIT

echo "=== running $N trials per arm (interleaved) ==="
for i in $(seq 1 "$N"); do
  bash "$BENCH_DIR/run-trial.sh" inner "$i"
  bash "$BENCH_DIR/run-trial.sh" outer "$i"
done

echo "=== collecting CircleCI minutes ==="
node "$BENCH_DIR/collect-ci.mjs" || echo "WARN: CI collection failed; re-run: node bench/collect-ci.mjs"

REPORT="report.md"
[[ "$BENCH_PHASE" == "2" ]] && REPORT="report-phase2.md"
echo "=== aggregating -> bench/${REPORT} ==="
BENCH_PHASE="$BENCH_PHASE" node "$BENCH_DIR/aggregate.mjs"

echo "=== DONE (phase ${BENCH_PHASE}). Grafana: http://localhost:3000  |  Report: bench/${REPORT} ==="
