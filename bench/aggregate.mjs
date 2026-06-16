#!/usr/bin/env node
// aggregate.mjs — read the raw per-trial files in bench/results/ and write
// bench/report.md: per-arm medians + spread and the inner-vs-outer deltas.
//
// Sources per trial <arm>-<trial>:
//   <label>.json          claude --output-format json result (cost, turns, tokens)
//   <label>.metrics.json  runner (wall_seconds, commits, claude_rc)
//   <label>.ci.json       CircleCI (ci_seconds, ci_pipelines)  [optional]
import { readdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const BENCH_DIR = dirname(fileURLToPath(import.meta.url));
const RESULTS = join(BENCH_DIR, "results");
const BENCH_PHASE = Number(process.env.BENCH_PHASE || "1");
const REPORT = BENCH_PHASE === 2 ? "report-phase2.md" : "report.md";

const readJSON = (p) => (existsSync(p) ? JSON.parse(readFileSync(p, "utf8")) : null);
const median = (xs) => {
  const a = xs.filter((x) => Number.isFinite(x)).sort((m, n) => m - n);
  if (!a.length) return NaN;
  const mid = Math.floor(a.length / 2);
  return a.length % 2 ? a[mid] : (a[mid - 1] + a[mid]) / 2;
};
const fmt = (x, d = 2) => (Number.isFinite(x) ? x.toFixed(d) : "—");

// collect trials from metrics sidecars (one per completed trial)
const trials = [];
for (const f of readdirSync(RESULTS).filter((f) => f.endsWith(".metrics.json"))) {
  const label = f.replace(".metrics.json", "");
  if (label.endsWith("-0")) continue; // skip dry-run trial 0
  const m = readJSON(join(RESULTS, f)) || {};
  const r = readJSON(join(RESULTS, `${label}.json`)) || {};
  const ci = readJSON(join(RESULTS, `${label}.ci.json`)) || {};
  const u = r.usage || {};
  const tokens =
    (u.input_tokens || 0) + (u.output_tokens || 0) +
    (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0);
  trials.push({
    arm: m.arm, trial: m.trial, phase: m.phase ?? BENCH_PHASE,
    wall: m.wall_seconds,
    cost: r.total_cost_usd ?? 0,
    turns: r.num_turns ?? 0,
    tokens,
    out_tokens: u.output_tokens || 0,
    iterations: m.iterations ?? NaN,
    commits: m.commits ?? NaN,
    ci_min: (ci.ci_seconds ?? NaN) / 60,
    pipelines: ci.ci_pipelines ?? NaN,
    is_error: m.is_error === true || r.is_error === true,
  });
}

// Phase filter: when running phase 2 aggregate, ignore phase-1 trials if tagged
const phaseTrials = trials.filter((t) => (t.phase ?? 1) === BENCH_PHASE);
const useTrials = phaseTrials.length ? phaseTrials : trials;

const arms = ["inner", "outer"];
const metrics = [
  ["Wall-clock to green (s)", "wall", 0],
  ["Cost per trial ($)", "cost", 4],
  ["Agent turns", "turns", 0],
  ["Total tokens", "tokens", 0],
  ["Output tokens", "out_tokens", 0],
  ["Outer harness iterations", "iterations", 0],
  ["Commits after base", "commits", 0],
  ["CI compute (min)", "ci_min", 1],
  ["CI pipelines", "pipelines", 0],
];

const byArm = Object.fromEntries(arms.map((a) => [a, useTrials.filter((t) => t.arm === a)]));

let md = `# Sidecar Benchmark — Inner vs Outer Loop`;
if (BENCH_PHASE === 2) md += ` (Phase 2: Iteration Economics)`;
md += `\n\n`;
md += `Inner loop = chunk-sidecar validation in the agent's lifecycle. `;
md += `Outer loop = traditional CI (push, read CircleCI, fix, repeat). `;
md += `Same task, same model; the only difference is how each arm validates.\n\n`;
md += `- inner trials: **${byArm.inner.length}**  ·  outer trials: **${byArm.outer.length}**`;
if (BENCH_PHASE === 2) md += `  ·  phase **2** (seeded WIP, multi-iteration target)`;
md += `\n`;
const errs = useTrials.filter((t) => t.is_error);
if (errs.length) md += `- ⚠️ ${errs.length} trial(s) ended with is_error=true: ${errs.map((t) => `${t.arm}-${t.trial}`).join(", ")}\n`;
// ---- shareable headline (the table you can paste into a deck/email) ----
const medOf = (a, key) => median(byArm[a].map((t) => t[key]));
const ratioOf = (key) => { const mi = medOf("inner", key), mo = medOf("outer", key); return mi ? mo / mi : NaN; };
const kfmt = (n) => (Number.isFinite(n) ? (n >= 1000 ? (n / 1000).toFixed(1) + "K" : String(Math.round(n))) : "—");
const qual = (key, suffix) => {
  const r = ratioOf(key);
  if (!Number.isFinite(r)) return "—";
  if (r === 1) return "equal";
  if (Math.abs(r - 1) <= 0.06) return `${r.toFixed(2)}× (≈equal)`;
  return `${r.toFixed(2)}× ${suffix}`;
};
md += `\n## Headline — Sidecar (inner) vs Traditional CI (outer)\n\n`;
md += `${byArm.inner.length} trials each, medians.\n\n`;
md += `| Metric | inner | outer | outer ÷ inner |\n|---|--:|--:|:--:|\n`;
md += `| **Wall-clock to green** | ${fmt(medOf("inner", "wall"), 0)} s | ${fmt(medOf("outer", "wall"), 0)} s | **${qual("wall", "slower")}** |\n`;
md += `| **Cost / change** | $${fmt(medOf("inner", "cost"), 3)} | $${fmt(medOf("outer", "cost"), 3)} | **${qual("cost", "more")}** |\n`;
md += `| **Total tokens** | ${kfmt(medOf("inner", "tokens"))} | ${kfmt(medOf("outer", "tokens"))} | **${qual("tokens", "more")}** |\n`;
md += `| Agent turns | ${fmt(medOf("inner", "turns"), 0)} | ${fmt(medOf("outer", "turns"), 0)} | ${qual("turns", "more")} |\n`;
md += `| **CI compute** | ${fmt(medOf("inner", "ci_min"), 1)} min | ${fmt(medOf("outer", "ci_min"), 1)} min | ${qual("ci_min", "more")} |\n`;
md += `| **CI pipelines** | ${fmt(medOf("inner", "pipelines"), 0)} | ${fmt(medOf("outer", "pipelines"), 0)} | ${qual("pipelines", "more")} |\n`;
if (BENCH_PHASE === 2) {
  const outerIters = median(byArm.outer.map((t) => t.iterations).filter(Number.isFinite));
  const outerCostPerIter = median(
    byArm.outer.filter((t) => t.iterations > 0).map((t) => t.cost / t.iterations),
  );
  md += `| Outer harness iterations (median) | — | ${fmt(outerIters, 0)} | — |\n`;
  md += `| Outer cost / CI iteration ($) | — | ${fmt(outerCostPerIter, 3)} | — |\n`;
}
if (BENCH_PHASE === 1) {
  md += `\n**What it means:** On a change that passes CI first-try, the sidecar / inner loop is faster and cheaper *per change* — the time win is the CI wait the outer loop pays even on success, and the token/cost win comes from fewer agent turns. CI minutes are ≈equal because both arms run exactly one pipeline; the CI-compute savings only show up when the outer loop has to **iterate**, which this simple task does not trigger.\n`;
} else {
  md += `\n**What it means:** Phase 2 seeds deliberate gate failures so the outer arm must push-and-wait multiple times. Compare **CI pipelines** and **cost per outer iteration** against Phase 1 (\`report.md\`) to quantify iteration economics. Inner arm should fix in sidecar before a single push.\n`;
  md += `\n_Plan: [PHASE2.md](./PHASE2.md)_\n`;
}

md += `\n## Medians (inner vs outer)\n\n`;
md += `| Metric | inner | outer | Δ (outer−inner) | outer / inner |\n|---|--:|--:|--:|--:|\n`;
for (const [name, key, d] of metrics) {
  const mi = median(byArm.inner.map((t) => t[key]));
  const mo = median(byArm.outer.map((t) => t[key]));
  const delta = mo - mi;
  const ratio = mi ? mo / mi : NaN;
  md += `| ${name} | ${fmt(mi, d)} | ${fmt(mo, d)} | ${fmt(delta, d)} | ${fmt(ratio, 2)}× |\n`;
}

md += `\n## Spread (min … median … max)\n\n`;
for (const [name, key, d] of metrics) {
  md += `**${name}**\n\n`;
  for (const a of arms) {
    const xs = byArm[a].map((t) => t[key]).filter(Number.isFinite);
    const mn = xs.length ? Math.min(...xs) : NaN;
    const mx = xs.length ? Math.max(...xs) : NaN;
    md += `- ${a}: ${fmt(mn, d)} … ${fmt(median(xs), d)} … ${fmt(mx, d)}\n`;
  }
  md += `\n`;
}

md += `## Per-trial detail\n\n`;
md += `| arm | trial | wall(s) | cost($) | turns | iters | tokens | CI(min) | pipelines | error |\n`;
md += `|---|--:|--:|--:|--:|--:|--:|--:|--:|:-:|\n`;
for (const t of useTrials.sort((a, b) => (a.arm + a.trial).localeCompare(b.arm + b.trial))) {
  md += `| ${t.arm} | ${t.trial} | ${fmt(t.wall, 0)} | ${fmt(t.cost, 4)} | ${t.turns} | ${fmt(t.iterations, 0)} | ${fmt(t.tokens, 0)} | ${fmt(t.ci_min, 1)} | ${fmt(t.pipelines, 0)} | ${t.is_error ? "✗" : "✓"} |\n`;
}
md += `\n_Live dashboard: http://localhost:3000/d/inner-vs-outer_\n`;

writeFileSync(join(BENCH_DIR, REPORT), md);
console.log(`aggregate: wrote bench/${REPORT} (${useTrials.length} trials: ${byArm.inner.length} inner, ${byArm.outer.length} outer)`);
