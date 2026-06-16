#!/usr/bin/env node
// collect-ci.mjs — for each trial branch (bench/<arm>-<trial>), query CircleCI
// for the pipelines that ran on it, sum job compute time, count pipelines, and
// push bench_ci_seconds / bench_ci_pipelines to the pushgateway (labelled
// loop/trial). Pipeline count == outer-loop iteration count (one per push).
//
// Needs CIRCLE_TOKEN (or CIRCLECI_TOKEN). Safe to re-run after pipelines finish.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const BENCH_DIR = dirname(fileURLToPath(import.meta.url));
const RESULTS = join(BENCH_DIR, "results");
const PUSHGW = process.env.PUSHGW || "http://localhost:9091";
const TOKEN = process.env.CIRCLE_TOKEN || process.env.CIRCLECI_TOKEN;
const SLUG =
  process.env.CIRCLECI_PROJECT_SLUG || "gh/ryan-circleci/demo-react-miniapps";
const API = "https://circleci.com/api/v2";

if (!TOKEN) {
  console.error("collect-ci: no CIRCLE_TOKEN/CIRCLECI_TOKEN set; skipping.");
  process.exit(0);
}

const headers = { "Circle-Token": TOKEN };
const get = async (path) => {
  const r = await fetch(`${API}${path}`, { headers });
  if (!r.ok) throw new Error(`${r.status} ${r.statusText} for ${path}`);
  return r.json();
};
const secs = (a, b) => (a && b ? Math.max(0, (new Date(b) - new Date(a)) / 1000) : 0);

async function ciForBranch(branch) {
  const pipelines = (await get(`/project/${encodeURIComponent(SLUG)}/pipeline?branch=${encodeURIComponent(branch)}`)).items || [];
  let jobSeconds = 0;
  for (const p of pipelines) {
    const wfs = (await get(`/pipeline/${p.id}/workflow`)).items || [];
    for (const wf of wfs) {
      const jobs = (await get(`/workflow/${wf.id}/job`)).items || [];
      for (const j of jobs) jobSeconds += secs(j.started_at, j.stopped_at);
    }
  }
  return { pipelines: pipelines.length, jobSeconds };
}

async function push(arm, trial, ciSeconds, ciPipelines) {
  const body =
    `# TYPE bench_ci_seconds gauge\nbench_ci_seconds ${ciSeconds}\n` +
    `# TYPE bench_ci_pipelines gauge\nbench_ci_pipelines ${ciPipelines}\n`;
  const url = `${PUSHGW}/metrics/job/bench/loop/${arm}/trial/${trial}`;
  const r = await fetch(url, { method: "POST", body });
  if (!r.ok) throw new Error(`pushgateway ${r.status}`);
}

const branchFiles = readdirSync(RESULTS).filter((f) => f.endsWith(".branch"));
if (!branchFiles.length) { console.error("collect-ci: no .branch files in results/"); process.exit(0); }

for (const f of branchFiles) {
  const [arm, trial] = f.replace(".branch", "").split("-");
  const branch = readFileSync(join(RESULTS, f), "utf8").trim();
  try {
    const { pipelines, jobSeconds } = await ciForBranch(branch);
    await push(arm, trial, jobSeconds, pipelines);
    writeFileSync(
      join(RESULTS, `${arm}-${trial}.ci.json`),
      JSON.stringify({ arm, trial, branch, ci_seconds: jobSeconds, ci_pipelines: pipelines }, null, 2),
    );
    console.log(`collect-ci: ${branch} -> ${pipelines} pipeline(s), ${(jobSeconds / 60).toFixed(1)} job-min`);
  } catch (e) {
    console.error(`collect-ci: ${branch} FAILED: ${e.message}`);
  }
}
