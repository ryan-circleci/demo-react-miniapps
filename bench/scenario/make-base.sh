#!/usr/bin/env bash
#
# make-base.sh [BASE_REF]   (default: origin/main)
#
# Builds the bench/base branch from BASE_REF, idempotently ensuring the reduced
# gate set (install + lint + Trivy + test + bundle × 2 mini-apps). Snyk is
# excluded — expired CI credential the agent cannot fix; Trivy is kept.
# main is aligned to this gate set; make-base is a no-op when already matched.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
START_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
restore_branch() { git checkout -q "$START_BRANCH" 2>/dev/null || true; }
trap restore_branch EXIT
BASE_REF="${1:-origin/main}"

git fetch -q origin main
git checkout -q -B bench/base "$BASE_REF"
git reset -q --hard "$BASE_REF"

# --- .chunk/config.json: drop any command whose name contains "snyk" ----------
jq '.commands |= map(select(.name | test("snyk") | not))' .chunk/config.json > .chunk/config.json.tmp
mv .chunk/config.json.tmp .chunk/config.json

# --- .circleci/config.yml: drop the Snyk run-step + the snyk installer --------
python3 - <<'PY'
p = ".circleci/config.yml"
lines = open(p).read().splitlines(keepends=True)
out, i = [], 0
while i < len(lines):
    l = lines[i]
    if "npm install -g snyk" in l:                       # drop snyk installer
        i += 1; continue
    if "name: Install scanners (Trivy + Snyk)" in l:     # rename installer step
        out.append(l.replace("Install scanners (Trivy + Snyk)", "Install scanner (Trivy)"))
        i += 1; continue
    if l.strip() == "- run:" and i + 1 < len(lines) and 'name: "Scan: Snyk' in lines[i + 1]:
        i += 3; continue                                 # drop the 3-line Snyk run block
    out.append(l); i += 1
open(p, "w").write("".join(out))
PY

# sanity: no executable Snyk left (comments are fine)
if grep -vE '^\s*#' .circleci/config.yml | grep -qE 'snyk test|install -g snyk'; then
  echo "ERROR: snyk still executed in CI config after edit" >&2; exit 1
fi
if [ "$(jq '[.commands[]|select(.name|test("snyk"))]|length' .chunk/config.json)" != "0" ]; then
  echo "ERROR: snyk gate still in .chunk/config.json after edit" >&2; exit 1
fi

git add .chunk/config.json .circleci/config.yml
if git diff --cached --quiet; then
  echo "bench/base already matches reduced gate set at $(git rev-parse --short HEAD)"
else
  git commit -q -m "bench: reduced gate set (drop Snyk; keep install/lint/Trivy/test/bundle)"
  echo "bench/base ready at $(git rev-parse --short HEAD) (gates: $(jq -r '[.commands[]|select(.role=="gate").name]|join(", ")' .chunk/config.json))"
fi
