# Inner-vs-Outer Loop Benchmark (OTEL-instrumented)

A controlled A/B that measures whether **chunk-sidecar inner-loop validation**
actually saves time, tokens, and money versus **traditional outer-loop CI**, for
an AI coding agent (Claude Code) doing the same task. Both arms are instrumented
with OpenTelemetry and shown side by side in Grafana.

- 📊 **Results:** [`report.md`](./report.md) — headline table + medians + spread + per-trial detail
- 🎤 **Presentation:** [`DEMO.md`](./DEMO.md) — the story for leadership/team
- 📈 **Live dashboard:** http://localhost:3000/d/inner-vs-outer (after the stack is up)

## The experiment

Two Claude Code agents, **identical** task / model / starting commit, run **5×**
each. The *only* difference is **how each validates**:

| | Inner loop | Outer loop |
|---|---|---|
| Validation | chunk-sidecar **Stop hook** (`chunk validate`) runs the gate set in seconds, every turn | traditional **commit → push → wait for CircleCI → fix → repeat** |
| Local checks | sidecar only | none (npm/jest/lint/chunk denied) |
| Config | `env/settings-inner.json` | `env/settings-outer.json` |

Both run the **same gate set** (lint + Trivy + tests + iOS bundle, for both
mini-apps). Snyk is dropped for the benchmark (expired CI credential, which an
agent can't fix) — applied equally to both arms so the comparison stays fair.

## How the data is captured

```
Claude Code ──OTLP──▶ otel-collector ──▶ Prometheus ──▶ Grafana
                                            ▲
        run scripts ──(wall-clock, CI minutes)──┘ via Pushgateway
```

- **OTEL** gives the agent-side metrics: tokens, cost, turns (tagged `loop=inner|outer`).
- The **run scripts** measure what OTEL can't: real wall-clock (incl. CI waits)
  and CI compute minutes (from the CircleCI API), pushed to the Pushgateway.
- Every figure is cross-checked against Claude Code's own per-run JSON.

For the outer arm, the scripts own the CI wait (push → block until the real
pipeline finishes → feed the result back via `--resume` → repeat), so the
outer-loop clock honestly includes the minutes a developer waits on CI.

## Run it yourself

```bash
# 1. bring up the OTEL stack (collector + prometheus + pushgateway + grafana)
docker compose -f bench/docker-compose.yml up -d

# 2. run the benchmark — 5 inner + 5 outer trials, from a PLAIN terminal
#    (not from inside an interactive Claude Code session in this repo: its Stop
#     hook would race the trials on the shared sidecar). Needs $CIRCLE_TOKEN.
bash bench/run-bench.sh 5

# 3. read the result, or watch live
open bench/report.md      # http://localhost:3000/d/inner-vs-outer
```

## File map

| Path | Purpose |
|---|---|
| `run-bench.sh` | orchestrator — runs all trials, then collect + aggregate |
| `run-trial.sh` | one trial (inner = single run; outer = push/wait/resume loop) |
| `outer-ci-wait.mjs` | waits for the real CircleCI pipeline, returns status + failure logs |
| `collect-ci.mjs` | pulls CI compute minutes per branch from the CircleCI API |
| `aggregate.mjs` | turns raw per-trial data into `report.md` |
| `scenario/` | the shared `TASK.md`, per-arm preambles, `make-base.sh` (reduced gate set) |
| `env/` | shared OTEL env + the two per-arm Claude settings (the one difference) |
| `docker-compose.yml`, `otel/`, `prometheus/`, `grafana/` | the observability stack |
| `results/` | raw per-trial output — **git-ignored**, regenerated each run |

## Caveats

See the bottom of `report.md` / `DEMO.md`: n=5, a single first-try-pass task
(so CI-minutes come out ≈equal — the CI-spend win compounds with *iterations*),
one contaminated inner trial excluded by using medians, and the reduced gate set.
This reproduces CircleCI's "Sidecar Race" experiment and adds the OTEL/Grafana
instrumentation layer.

## Phase 2: Iteration economics

Phase 1 measured the **floor** (first-try green). Phase 2 forces multiple fix
cycles via a seeded WIP on `bench/base-phase2`. See **[PHASE2.md](./PHASE2.md)**.

```bash
# Dry run (one trial per arm)
bash bench/scenario/make-base.sh && bash bench/scenario/make-base-phase2.sh
BENCH_PHASE=2 bash bench/run-trial.sh outer 0

# Full batch
BENCH_PHASE=2 bash bench/run-bench.sh 5
# Report: bench/report-phase2.md
```
