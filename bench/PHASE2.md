# Phase 2: Iteration Economics (Inner vs Outer Loop)

**Branch:** `bench/phase2-iteration-economics`  
**Status:** Planning — harness scaffolded, not yet run  
**Predecessor:** Phase 1 (`bench/report.md`) — first-try-pass floor case  
**Loop Lab sequel:** [The Sidecar Race](https://loop.circleci.com/the-sidecar-race-22-seconds-vs-69-seconds-inside-the-agent-loop) (TTS); Phase 1 draft (loop-overhead tokens)

---

## Why Phase 2 exists

Phase 1 answered a narrow question well:

> *Even when CI passes on the first push, does the outer loop cost more in tokens?*

**Yes** — ~1.4× cost, ~1.8× tokens (medians, n=5). But every trial passed CI on attempt 1, so **CI compute was ≈ equal**. The compounding story — extra pipelines × extra wait × extra log-reading turns — was not measured.

Phase 2 forces **multiple fix cycles** so we can report:

| Metric | Phase 1 | Phase 2 (target) |
|---|---|---|
| Primary claim | Loop-overhead tokens on success | **Cost per green iteration** + CI compounding |
| CI pipelines (outer) | 1 (all trials) | **≥ 2 median**, ideally 2–3 |
| CI pipelines (inner) | 1 | **1** (fix in sidecar before push) |
| Sidecar validation cycles | ~6 turns | **≥ 2** deliberate gate failures |
| Task difficulty | Single-file, greenfield | Multi-app, seeded WIP with known defects |

---

## Hypothesis

If an agent completes the same multi-app change with **seeded gate failures** (lint, then test), then:

1. **Outer arm** will trigger **≥ 2 CircleCI pipelines** per trial (one per push-and-wait cycle).
2. **Inner arm** will absorb failures via **sidecar Stop-hook validation** in seconds, finishing with **1 pipeline** (single push after sidecar green).
3. **LLM cost and tokens** on the outer arm will exceed Phase 1's outer medians — not only loop overhead, but **CI log ingestion and resume turns** per failed pipeline.
4. **Wall-clock** gap vs Phase 1 widens: each outer iteration adds ~2–3 min CI wait; inner adds ~20–30 s sidecar wait.

We are **not** claiming universal 40% savings. We are measuring **iteration economics** under a controlled, reproducible task.

---

## Experimental design

### Controlled variables (unchanged from Phase 1)

- Same repo, model, gate set (install + lint + Trivy + test + bundle × 2 mini-apps)
- Same `settings-inner.json` / `settings-outer.json` permission model
- Same OTEL stack, interleaved trials, throwaway branches `bench/<arm>-<trial>`
- Snyk dropped on `bench/base` (applied equally to both arms)

### Independent variable

**Starting state + task** — agents begin from `bench/base-phase2`, which includes a **deliberately broken WIP** on Payments (see [make-base-phase2.sh](./scenario/make-base-phase2.sh)).

### Dependent variables

| Metric | Source |
|---|---|
| Wall-clock to green | `run-trial.sh` → `.metrics.json` |
| LLM cost ($) | Claude `--output-format json` |
| Total tokens (in/out/cache) | JSON usage + OTEL |
| Agent turns | JSON `num_turns` |
| Outer harness iterations | `iterations` in `.metrics.json` |
| CI pipelines | `collect-ci.mjs` → `.ci.json` |
| CI compute (job-min) | `collect-ci.mjs` |
| Commits after base | `git rev-list --count` in `run-trial.sh` |

**New derived metrics** (aggregate Phase 2 report):

- **Cost per outer CI iteration** = `cost_usd / iterations` (outer only)
- **Δ CI pipelines** = outer median pipelines − inner median pipelines
- **Δ CI compute** = outer median job-min − inner median job-min

---

## Task design (Phase 2)

See [scenario/TASK-phase2.md](./scenario/TASK-phase2.md).

**Summary:** Complete a partially implemented Payments welcome screen (fix lint + tests), then add a matching personalized subtitle to Transfers with an updated test. Both mini-apps must pass all gates.

**Why this task:**

1. **Seeded lint failure** — WIP uses `TouchableOpacity` without importing it → reliable first gate fail.
2. **Test gap** — WIP adds UI but leaves old test unchanged until agent updates it → second fail if agent fixes lint first without tests.
3. **Multi-app** — Transfers change ensures both app gate sets run; mirrors real monorepo work.
4. **Agent-canonical fixes** — failures are ordinary ESLint/Jest errors, not credential or infra issues.

---

## Seeded baseline (`bench/base-phase2`)

Built by:

```bash
bash bench/scenario/make-base.sh          # bench/base (Snyk-free gates)
bash bench/scenario/make-base-phase2.sh   # bench/base-phase2 (seeded WIP)
```

**Payments `App.js` (seeded):**

- Subtitle + `Send money` button present in JSX
- `handleSend` defined
- **`TouchableOpacity` used but not imported** → ESLint `react/jsx-no-undef` / no-undef

**Payments test (seeded):**

- Still asserts only `Welcome to Payments` — does **not** assert the new button → passes until agent breaks something else, or we optionally seed a **wrong** button assertion

**Optional second seed (recommended after dry-run):** If agents fix lint + add test in one turn too often, add to test file:

```javascript
expect(getByText('Send Money')).toBeTruthy(); // wrong casing — fails until fixed
```

**Transfers:** Clean baseline (no WIP). Task requires new subtitle + test assertion.

---

## Arm-specific workflow tweaks (Phase 2 only)

### Inner (`preamble-inner-phase2.md`)

Phase 1 preamble encouraged push-before-green, which collapsed CI pipeline count to 1 on both arms. Phase 2 **tightens inner workflow** to match the sidecar-race model:

1. Edit locally → end turn → **sidecar validates** (seconds).
2. Fix until sidecar reports **no failures**.
3. **Then** commit and push **once**.
4. Done when pushed and sidecar is green.

This isolates **CI pipeline count** as a dependent variable: inner should stay at **1 pipeline**; outer scales with failed pushes.

### Outer (`preamble-outer-phase2.md`)

Unchanged model: commit → push → stop → harness waits for CI → resume with logs. Each failed pipeline = one outer iteration.

---

## Success criteria (before writing Loop Lab Piece 2)

Run `BENCH_PHASE=2 bash bench/run-bench.sh 5` and check:

| Criterion | Target |
|---|---|
| Outer median CI pipelines | ≥ 2.0 |
| Inner median CI pipelines | ≤ 1.2 |
| Outer median cost / inner median cost | ≥ 1.5× (stricter than Phase 1's 1.39×) |
| Outer median wall / inner median wall | ≥ 2.0× |
| Trial success rate | ≥ 8/10 trials reach green (`is_error=false`) |
| Seeded failures observed | Outer `iterations` ≥ 2 in ≥ 4/5 outer trials |

If outer pipelines stay at 1, **strengthen the seed** (wrong test assertion, add unused var in Transfers stub) and dry-run one manual trial before a full batch.

---

## Execution checklist

### One-time setup

```bash
git checkout bench/phase2-iteration-economics
docker compose -f bench/docker-compose.yml up -d
chunk sidecar current   # or create one
export CIRCLE_TOKEN=... # for CI minute collection
```

### Dry run (single trial per arm)

```bash
bash bench/scenario/make-base.sh
bash bench/scenario/make-base-phase2.sh
BENCH_PHASE=2 bash bench/run-trial.sh inner 0   # optional: trial 0 excluded from aggregate
BENCH_PHASE=2 bash bench/run-trial.sh outer 0
# Inspect bench/results/outer-0.metrics.json — iterations should be ≥ 2
```

### Full batch

```bash
BENCH_PHASE=2 bash bench/run-bench.sh 5
# Report: bench/report-phase2.md
```

### After run

1. Review Grafana dashboard (`loop=inner|outer`, trial labels)
2. Verify `bench/report-phase2.md` headline table
3. Archive raw `bench/results/` (gitignored) to a dated artifact path or tag
4. Update this doc's **Status** section with actual medians

---

## Risk register

| Risk | Mitigation |
|---|---|
| Agent fixes everything in one turn | Stronger seeds; wrong test assertion; pilot trial before batch |
| Inner agent pushes before sidecar green | Phase 2 inner preamble; monitor `commits` and pipeline count |
| High variance (n=5) | Report medians + spread; consider n=10 if budget allows |
| Shared sidecar contamination | Interleaved trials; exclude outliers (as with Phase 1 `inner-1`) |
| Outer timeout (900s) | `OUTER_MAX_ITERS=6` default; raise if pipelines are slow |
| Task too hard — agents don't finish | Loosen task wording; reduce Transfers scope; increase MAX_ITERS |

---

## Content mapping (Loop Lab)

| Piece | Data source | Claim |
|---|---|---|
| **Piece 1 (now)** | Phase 1 `report.md` | Loop-overhead tokens; first-try-pass floor |
| **Piece 2 (after Phase 2)** | `report-phase2.md` | Iteration economics; CI × token compounding |

**Suggested Piece 2 title:** *"The Iteration Tax: Sidecar vs CI When Agents Don't Get It First Try"*

**Bridge sentence:** Phase 1 showed outer loop costs more even on your best day. Phase 2 measures what happens on a normal day — when lint and tests fail twice before green.

---

## File map (Phase 2 additions)

| Path | Purpose |
|---|---|
| `PHASE2.md` | This plan |
| `scenario/TASK-phase2.md` | Agent task prompt |
| `scenario/make-base-phase2.sh` | Builds `bench/base-phase2` with seeded WIP |
| `scenario/preamble-inner-phase2.md` | Push-after-green inner workflow |
| `scenario/preamble-outer-phase2.md` | Outer loop (same as Phase 1 + phase label) |
| `run-bench.sh` | Honors `BENCH_PHASE=2` |
| `run-trial.sh` | Selects phase-specific task/preambles/base ref |
| `aggregate.mjs` | Writes `report-phase2.md` with iteration metrics |

---

## CI prerequisites

CircleCI must be set up on the repo that receives agent pushes (default: `origin`).

- **Project:** [ryan-circleci/demo-react-miniapps](https://app.circleci.com/pipelines/github/ryan-circleci/demo-react-miniapps)
- **Harness slug:** `gh/ryan-circleci/demo-react-miniapps` (override with `CIRCLECI_PROJECT_SLUG`)
- **Snyk:** dropped from the default pipeline; bench uses the same Trivy-only gate set via `make-base.sh`

---

## Next steps

- [ ] Dry-run `outer` trial — confirm ≥ 2 CI pipelines
- [ ] Dry-run `inner` trial — confirm 1 pipeline, sidecar catches lint before push
- [ ] Tune seed if needed
- [ ] Run full 5×2 batch
- [ ] Draft Loop Lab Piece 2 from `report-phase2.md`
