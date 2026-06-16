#!/usr/bin/env bash
#
# trial-pr.sh open|finalize LABEL ARM TRIAL PHASE BASE_SHA [CI_STATUS]
#
# Opens a draft PR when a bench trial branch is pushed, then marks it ready for
# review when the run finishes with green CI. PRs are experiment artifacts.
#
# Env:
#   BENCH_OPEN_PR=0     disable PR automation
#   BENCH_GH_REPO=      override (default: origin remote via gh)
#   BENCH_PR_BASE=main  PR base branch
set -euo pipefail

ACTION="${1:?usage: trial-pr.sh <open|finalize> ...}"
LABEL="${2:?}"
ARM="${3:?}"
TRIAL="${4:?}"
PHASE="${5:?}"
BASE_SHA="${6:-}"
CI_STATUS="${7:-unknown}"

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BENCH_DIR/.." && pwd)"
RESULTS="$BENCH_DIR/results"
BRANCH="bench/${LABEL}"
PR_JSON="$RESULTS/${LABEL}.pr.json"
PR_BASE="${BENCH_PR_BASE:-main}"

gh_repo() {
  if [[ -n "${BENCH_GH_REPO:-}" ]]; then
    echo "$BENCH_GH_REPO"
    return
  fi
  gh repo view --json nameWithOwner -q .nameWithOwner --remote origin 2>/dev/null \
    || gh repo view --json nameWithOwner -q .nameWithOwner
}

pr_body_initial() {
  cat <<EOF
## Bench trial artifact

| Field | Value |
|---|---|
| Phase | ${PHASE} |
| Arm | ${ARM} |
| Trial | ${TRIAL} |
| Branch | \`${BRANCH}\` |
| Base | \`${BASE_SHA:0:8}\` |

_Experiment in progress. This draft PR documents the agent run commit-by-commit._

Each push on this branch triggers CI. When the trial completes with all gates green, this PR will be marked ready for review.

### Local results
- \`bench/results/${LABEL}.json\`
- \`bench/results/${LABEL}.metrics.json\`
- \`bench/results/${LABEL}.ci.json\`
EOF
}

pr_body_finalize() {
  local m="$RESULTS/${LABEL}.metrics.json"
  local wall cost turns iters commits ci
  wall="$(jq -r '.wall_seconds // "—"' "$m" 2>/dev/null || echo "—")"
  cost="$(jq -r '.cost_usd // "—"' "$m" 2>/dev/null || echo "—")"
  turns="$(jq -r '.turns // "—"' "$m" 2>/dev/null || echo "—")"
  iters="$(jq -r '.iterations // "—"' "$m" 2>/dev/null || echo "—")"
  commits="$(jq -r '.commits // "—"' "$m" 2>/dev/null || echo "—")"
  ci="$(jq -r '.ci_status // "—"' "$m" 2>/dev/null || echo "—")"
  cat <<EOF
## Bench trial artifact

| Field | Value |
|---|---|
| Phase | ${PHASE} |
| Arm | ${ARM} |
| Trial | ${TRIAL} |
| Branch | \`${BRANCH}\` |
| Base | \`${BASE_SHA:0:8}\` |
| **Status** | **${CI_STATUS}** |

### Run summary

| Metric | Value |
|---|---|
| Wall-clock (s) | ${wall} |
| Cost (USD) | ${cost} |
| Agent turns | ${turns} |
| Harness iterations | ${iters} |
| Commits after base | ${commits} |
| CI status | ${ci} |

### Local results
- \`bench/results/${LABEL}.json\`
- \`bench/results/${LABEL}.metrics.json\`
- \`bench/results/${LABEL}.ci.json\`

$( [[ "$CI_STATUS" == "success" ]] && echo "All CI gates passed. Ready for review." || echo "Trial ended without green CI — left as draft for inspection." )
EOF
}

pr_title() {
  echo "bench: phase ${PHASE} ${ARM} trial ${TRIAL} (${LABEL})"
}

existing_pr_number() {
  local repo="$1"
  gh pr list --repo "$repo" --head "$BRANCH" --state all --json number,url \
    -q '.[0].number // empty' 2>/dev/null || true
}

case "$ACTION" in
  open)
    [[ "${BENCH_OPEN_PR:-1}" == "1" ]] || exit 0
    command -v gh >/dev/null || { echo "WARN: gh not found — skipping trial PR"; exit 0; }
    REPO="$(gh_repo)" || { echo "WARN: could not resolve GitHub repo"; exit 0; }

    NUM="$(existing_pr_number "$REPO")"
    if [[ -n "$NUM" ]]; then
      URL="$(gh pr view "$NUM" --repo "$REPO" --json url -q .url)"
      echo "==> [$LABEL] draft PR already exists: $URL"
    else
      URL="$(gh pr create --repo "$REPO" --base "$PR_BASE" --head "$BRANCH" --draft \
        --title "$(pr_title)" --body "$(pr_body_initial)" 2>/dev/null)" \
        || { echo "WARN: draft PR create failed for $BRANCH"; exit 0; }
      NUM="$(existing_pr_number "$REPO")"
      echo "==> [$LABEL] opened draft PR #$NUM: $URL"
    fi
    printf '{"repo":"%s","number":%s,"url":"%s","branch":"%s"}\n' \
      "$REPO" "${NUM:-null}" "$URL" "$BRANCH" > "$PR_JSON"
    ;;

  finalize)
    [[ "${BENCH_OPEN_PR:-1}" == "1" ]] || exit 0
    command -v gh >/dev/null || exit 0
    [[ -f "$PR_JSON" ]] || exit 0
    REPO="$(jq -r '.repo' "$PR_JSON")"
    NUM="$(jq -r '.number' "$PR_JSON")"
    [[ -n "$NUM" && "$NUM" != "null" ]] || exit 0

    gh pr edit "$NUM" --repo "$REPO" --body "$(pr_body_finalize)" 2>/dev/null \
      || echo "WARN: could not update PR body for #$NUM"

    if [[ "$CI_STATUS" == "success" ]]; then
      gh pr ready "$NUM" --repo "$REPO" 2>/dev/null \
        && echo "==> [$LABEL] PR #$NUM marked ready for review" \
        || echo "WARN: could not mark PR #$NUM ready"
    else
      echo "==> [$LABEL] PR #$NUM left as draft (ci=${CI_STATUS})"
    fi
    ;;

  *)
    echo "ERROR: unknown action $ACTION" >&2
    exit 2
    ;;
esac
