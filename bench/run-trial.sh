#!/usr/bin/env bash
#
# run-trial.sh ARM TRIAL
#   ARM   = inner | outer
#   TRIAL = integer trial number (1..N)
#
# Runs ONE Claude Code trial for ONE arm, headless, on a fresh throwaway branch
# bench/<arm>-<trial> cut from origin/main (byte-identical start, isolated CI).
#
# Captures:
#   - the --output-format json result  -> bench/results/<arm>-<trial>.json
#   - OTEL metrics (shared.env -> collector -> prometheus), labelled loop/trial
#   - harness metrics (wall clock, cost, turns, commits, branch) -> pushgateway
#
# The ONLY difference between arms is bench/env/settings-<arm>.json (sidecar Stop
# hook for inner; CI-only, local-validation-denied for outer) and the preamble.
set -euo pipefail

ARM="${1:?usage: run-trial.sh <inner|outer> <trial>}"
TRIAL="${2:?usage: run-trial.sh <inner|outer> <trial>}"
[[ "$ARM" == "inner" || "$ARM" == "outer" ]] || { echo "ARM must be inner|outer"; exit 2; }

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BENCH_DIR/.." && pwd)"
RESULTS="$BENCH_DIR/results"
PUSHGW="${PUSHGW:-http://localhost:9091}"
mkdir -p "$RESULTS"
cd "$REPO_ROOT"

if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
  echo "ERROR: git rebase in progress — run: git rebase --abort" >&2
  exit 1
fi

BENCH_PHASE="${BENCH_PHASE:-1}"
case "$BENCH_PHASE" in
  1) TASK_FILE="TASK.md"; PREAMBLE_SUFFIX="" ;;
  2) TASK_FILE="TASK-phase2.md"; PREAMBLE_SUFFIX="-phase2" ;;
  *) echo "ERROR: BENCH_PHASE must be 1 or 2 (got: $BENCH_PHASE)"; exit 2 ;;
esac

LABEL="${ARM}-${TRIAL}"
BRANCH="bench/${LABEL}"
RESULT_JSON="$RESULTS/${LABEL}.json"
RUN_LOG="$RESULTS/${LABEL}.log"

# Load harness inputs BEFORE cutting the trial branch. Trial branches are cut
# from bench/base (origin/main lineage) and do not carry phase-specific scenario
# files — checkout would delete them from the working tree.
PROMPT="$(cat "$BENCH_DIR/scenario/preamble-${ARM}${PREAMBLE_SUFFIX}.md"; echo; cat "$BENCH_DIR/scenario/${TASK_FILE}")"
SETTINGS="$(cat "$BENCH_DIR/env/settings-${ARM}.json")"
# Trial branches are cut from bench/base* and do not carry harness scripts; cache
# trial-pr.sh before checkout deletes it from the working tree.
TRIAL_PR=""
if [[ -f "$BENCH_DIR/trial-pr.sh" ]]; then
  TRIAL_PR="$RESULTS/.trial-pr.sh"
  cp "$BENCH_DIR/trial-pr.sh" "$TRIAL_PR"
  chmod +x "$TRIAL_PR"
fi
# shellcheck disable=SC1091
source "$BENCH_DIR/env/shared.env"
export OTEL_RESOURCE_ATTRIBUTES="loop=${ARM},trial=${TRIAL}"

# cut each trial from the reduced-gate base branch (built by make-base.sh), so
# both arms validate the same Snyk-free gate set. Override with BENCH_BASE_REF.
if [[ -z "${BENCH_BASE_REF:-}" ]]; then
  BENCH_BASE_REF="bench/base"
  [[ "$BENCH_PHASE" == "2" ]] && BENCH_BASE_REF="bench/base-phase2"
fi
BASE_REF="$BENCH_BASE_REF"
git rev-parse --verify -q "$BASE_REF" >/dev/null || { echo "ERROR: $BASE_REF missing — run bench/scenario/make-base.sh"; exit 1; }
if [[ "$BENCH_PHASE" == "2" ]]; then
  git show "$BASE_REF:miniapps/payments/src/App.js" | rg -q 'pendingTransfers' || {
    echo "ERROR: $BASE_REF missing strong phase2 seed — run: bash bench/scenario/make-base-phase2.sh && bash bench/scenario/verify-phase2-seed.sh" >&2
    exit 1
  }
fi
echo "==> [$LABEL] fresh branch $BRANCH from $BASE_REF ($(git rev-parse --short "$BASE_REF"))"
git checkout -q -B "$BRANCH" "$BASE_REF"
git reset -q --hard "$BASE_REF"          # byte-identical start; discards any leftover swap
BASE_SHA="$(git rev-parse HEAD)"
git push -u origin "$BRANCH" --force
if [[ -n "$TRIAL_PR" ]]; then
  bash "$TRIAL_PR" open "$LABEL" "$ARM" "$TRIAL" "$BENCH_PHASE" "$BASE_SHA" || true
fi

# arm-specific Claude settings (working-tree change; fine if the agent commits it
# on this throwaway branch — CircleCI does not read .claude/).
mkdir -p "$REPO_ROOT/.claude"
printf '%s\n' "$SETTINGS" > "$REPO_ROOT/.claude/settings.json"

ITERS=1; CI_STATUS="n/a"
if [[ "$ARM" == "inner" ]]; then
  # INNER: single invocation. The sidecar Stop hook validates after every turn
  # and drives the agent to green within this one call (seconds per cycle).
  echo "==> [$LABEL] running claude (inner, single invocation; sidecar drives validation)"
  START=$(date +%s)
  set +e
  claude -p "$PROMPT" --output-format json --permission-mode acceptEdits >"$RESULT_JSON" 2>"$RUN_LOG"
  CLAUDE_RC=$?
  set -e
  END=$(date +%s); WALL=$((END - START))
  COST=$(jq -r '.total_cost_usd // 0'   "$RESULT_JSON" 2>/dev/null || echo 0)
  TURNS=$(jq -r '.num_turns // 0'       "$RESULT_JSON" 2>/dev/null || echo 0)
  DUR_MS=$(jq -r '.duration_ms // 0'    "$RESULT_JSON" 2>/dev/null || echo 0)
  IS_ERROR=$(jq -r '.is_error // false' "$RESULT_JSON" 2>/dev/null || echo true)
  HEAD_AFTER="$(git rev-parse HEAD)"
  COMMITS=$(git rev-list --count "${BASE_SHA}..${HEAD_AFTER}" 2>/dev/null || echo 0)
  CI_STATUS="n/a"
  if [[ "$COMMITS" -gt 0 ]]; then
    echo "==> [$LABEL] waiting for CI on $BRANCH @ ${HEAD_AFTER:0:8} ..."
    CIW=$(node "$BENCH_DIR/outer-ci-wait.mjs" "$BRANCH" "$HEAD_AFTER" 900 2>>"$RUN_LOG" | tail -1)
    CI_STATUS=$(echo "$CIW" | jq -r '.status // "error"' 2>/dev/null || echo error)
    echo "==> [$LABEL] CI -> $CI_STATUS"
    [[ "$CI_STATUS" != "success" ]] && IS_ERROR=true
  fi
else
  # OUTER: harness-driven push -> WAIT for CI -> resume with failure logs -> repeat.
  # A single headless call can't faithfully wait minutes for CI, so the harness
  # owns the wait. The wall clock therefore INCLUDES the real CI waits, which is
  # the true outer-loop time-to-green. The agent only does the fix work.
  MAX_ITERS="${OUTER_MAX_ITERS:-6}"
  CLAUDE_RC=0; COST=0; TURNS=0; DUR_MS=0; IS_ERROR=false; CI_STATUS="unknown"; SID=""; FEEDBACK=""
  START=$(date +%s); ITERS=0
  while [ "$ITERS" -lt "$MAX_ITERS" ]; do
    ITERS=$((ITERS + 1))
    ij="$RESULTS/${LABEL}.iter${ITERS}.json"
    echo "==> [$LABEL] outer iteration $ITERS (agent: edit/commit/push, then stop)"
    set +e
    if [ -z "$SID" ]; then
      claude -p "$PROMPT" --output-format json --permission-mode acceptEdits >"$ij" 2>>"$RUN_LOG"
    else
      claude -p --resume "$SID" "$FEEDBACK" --output-format json --permission-mode acceptEdits >"$ij" 2>>"$RUN_LOG"
    fi
    CLAUDE_RC=$?
    set -e
    SID=$(jq -r '.session_id // empty' "$ij" 2>/dev/null || true)
    COST=$(awk -v a="$COST" -v b="$(jq -r '.total_cost_usd // 0' "$ij" 2>/dev/null || echo 0)" 'BEGIN{printf "%.6f", a+b}')
    TURNS=$((TURNS + $(jq -r '.num_turns // 0' "$ij" 2>/dev/null || echo 0)))
    DUR_MS=$((DUR_MS + $(jq -r '.duration_ms // 0' "$ij" 2>/dev/null || echo 0)))
    cp "$ij" "$RESULT_JSON"
    HEAD_NOW="$(git rev-parse HEAD)"
    echo "==> [$LABEL] waiting for CI on $BRANCH @ ${HEAD_NOW:0:8} ..."
    CIW=$(node "$BENCH_DIR/outer-ci-wait.mjs" "$BRANCH" "$HEAD_NOW" 900 2>>"$RUN_LOG" | tail -1)
    CI_STATUS=$(echo "$CIW" | jq -r '.status // "error"' 2>/dev/null || echo error)
    echo "==> [$LABEL] CI iteration $ITERS -> $CI_STATUS"
    [ "$CI_STATUS" = "success" ] && break
    if [ "$CI_STATUS" != "failed" ]; then echo "==> [$LABEL] CI $CI_STATUS — stopping outer loop"; break; fi
    FEEDBACK="The CI pipeline for this branch FAILED. You cannot validate locally; CI is your only signal. Failure logs:

$(echo "$CIW" | jq -r '.feedback // "no logs"' 2>/dev/null)

Fix the problem, commit, and push again, then stop. Do not poll CI yourself — you will be told the new result."
    if [[ "$BENCH_PHASE" == "2" ]]; then
      FEEDBACK="${FEEDBACK}

Phase 2 rules: complete Milestone 1 (Payments only) before editing miniapps/transfers/. Ignore Transfers failures until Payments is CI-clean. Do not git pull, git fetch, or rebase — push only."
    fi
  done
  END=$(date +%s); WALL=$((END - START))
  [ "$CI_STATUS" = "success" ] && IS_ERROR=false || IS_ERROR=true
  HEAD_AFTER="$(git rev-parse HEAD)"
  COMMITS=$(git rev-list --count "${BASE_SHA}..${HEAD_AFTER}" 2>/dev/null || echo 0)
fi

HEAD_AFTER="$(git rev-parse HEAD)"
COMMITS=$(git rev-list --count "${BASE_SHA}..${HEAD_AFTER}" 2>/dev/null || echo 0)

echo "==> [$LABEL] done rc=$CLAUDE_RC wall=${WALL}s cost=\$${COST} turns=${TURNS} iters=${ITERS} commits=${COMMITS} ci=${CI_STATUS} is_error=${IS_ERROR}"

# record the branch so collect-ci.mjs knows where to find this trial's pipelines
echo "$BRANCH" > "$RESULTS/${LABEL}.branch"

# local metrics sidecar so aggregate.mjs can build the report from raw files
cat > "$RESULTS/${LABEL}.metrics.json" <<EOF
{ "arm": "${ARM}", "trial": ${TRIAL}, "branch": "${BRANCH}", "phase": ${BENCH_PHASE},
  "wall_seconds": ${WALL}, "claude_rc": ${CLAUDE_RC}, "commits": ${COMMITS},
  "iterations": ${ITERS}, "ci_status": "${CI_STATUS}",
  "cost_usd": ${COST}, "turns": ${TURNS}, "is_error": ${IS_ERROR} }
EOF

if [[ -n "$TRIAL_PR" ]]; then
  bash "$TRIAL_PR" finalize "$LABEL" "$ARM" "$TRIAL" "$BENCH_PHASE" "$BASE_SHA" "$CI_STATUS" || true
fi
if [[ -n "$TRIAL_PR" ]] && [[ -f "$RESULTS/${LABEL}.pr.json" ]]; then
  PR_URL="$(jq -r '.url // ""' "$RESULTS/${LABEL}.pr.json" 2>/dev/null || true)"
  if [[ -n "$PR_URL" ]]; then
    jq --arg url "$PR_URL" '. + {pr_url: $url}' "$RESULTS/${LABEL}.metrics.json" > "$RESULTS/${LABEL}.metrics.json.tmp"
    mv "$RESULTS/${LABEL}.metrics.json.tmp" "$RESULTS/${LABEL}.metrics.json"
  fi
fi

# harness metrics (CI minutes + pipeline count are added later by collect-ci.mjs)
curl -fsS --data-binary @- "${PUSHGW}/metrics/job/bench/loop/${ARM}/trial/${TRIAL}" <<EOF || echo "WARN: pushgateway unreachable"
# TYPE bench_wall_clock_seconds gauge
bench_wall_clock_seconds ${WALL}
# TYPE bench_cost_usd gauge
bench_cost_usd ${COST}
# TYPE bench_turns gauge
bench_turns ${TURNS}
# TYPE bench_agent_duration_ms gauge
bench_agent_duration_ms ${DUR_MS}
# TYPE bench_commits gauge
bench_commits ${COMMITS}
# TYPE bench_iterations gauge
bench_iterations ${ITERS}
EOF

echo "$LABEL"
