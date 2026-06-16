#!/usr/bin/env node
// outer-ci-wait.mjs <branch> <revision> [maxWaitSec]
//
// Used by the OUTER arm of run-trial.sh. Waits for the CircleCI pipeline of the
// given branch/commit to finish, then prints a JSON line to stdout:
//   { "status": "success"|"failed"|"timeout"|"error", "pipelineNumber": N, "feedback": "..." }
// On failure, `feedback` holds the failed step names + truncated log output so
// the harness can inject it into the agent via `claude -p --resume`.
//
// This makes the outer loop's CI wait DETERMINISTIC and part of the wall clock,
// instead of relying on the agent to idle-poll (which it won't do in headless).
const [, , BRANCH, REVISION, MAX] = process.argv;
const TOKEN = process.env.CIRCLE_TOKEN || process.env.CIRCLECI_TOKEN;
const SLUG =
  process.env.CIRCLECI_PROJECT_SLUG || "gh/ryan-circleci/demo-react-miniapps";
const API = "https://circleci.com/api/v2";
const V1 = "https://circleci.com/api/v1.1/project/" + SLUG;
const maxWaitSec = Number(MAX || 900);

const out = (o) => { process.stdout.write(JSON.stringify(o) + "\n"); };
if (!TOKEN) { out({ status: "error", feedback: "no CIRCLE_TOKEN" }); process.exit(0); }
const h = { "Circle-Token": TOKEN };
const get = async (u) => { const r = await fetch(u, { headers: h }); if (!r.ok) throw new Error(`${r.status} ${u}`); return r.json(); };
const sleep = (s) => new Promise((r) => setTimeout(r, s * 1000));
const strip = (s) => s.replace(/\[[0-9;]*m/g, "");

async function findPipeline() {
  const items = (await get(`${API}/project/${encodeURIComponent(SLUG)}/pipeline?branch=${encodeURIComponent(BRANCH)}`)).items || [];
  // With a revision, ONLY accept its pipeline; if not created yet, return null so
  // we keep waiting (never fall back to a stale earlier-iteration pipeline).
  if (REVISION) return items.find((p) => p.vcs && p.vcs.revision && p.vcs.revision.startsWith(REVISION)) || null;
  return items[0] || null;
}

async function failureFeedback(workflows) {
  const parts = [];
  for (const wf of workflows) {
    const jobs = (await get(`${API}/workflow/${wf.id}/job`)).items || [];
    for (const j of jobs.filter((x) => x.status === "failed" && x.job_number)) {
      let detail = "";
      try {
        const jd = await get(`${V1}/${j.job_number}?circle-token=${TOKEN}`);
        for (const step of jd.steps || []) {
          for (const a of step.actions || []) {
            if (a.failed || a.status === "failed") {
              let txt = "";
              try { const r = await fetch(a.output_url); const t = await r.text();
                try { txt = JSON.parse(t).map((m) => m.message).join(""); } catch { txt = t; } } catch {}
              detail += `\n  step "${step.name}" (exit ${a.exit_code}):\n${strip(txt).split("\n").slice(-25).join("\n")}\n`;
            }
          }
        }
      } catch (e) { detail = ` (could not fetch step logs: ${e.message})`; }
      parts.push(`Job "${j.name}" FAILED:${detail}`);
    }
  }
  return parts.join("\n\n").slice(0, 6000) || "CI failed but no failed-job detail was retrievable.";
}

(async () => {
  const deadline = maxWaitSec;
  let waited = 0;
  try {
    while (waited <= deadline) {
      const p = await findPipeline();
      if (p) {
        const wfs = (await get(`${API}/pipeline/${p.id}/workflow`)).items || [];
        const pending = wfs.filter((w) => ["running", "on_hold", "not_run"].includes(w.status) || w.status == null);
        if (wfs.length && pending.length === 0) {
          const failed = wfs.some((w) => ["failed", "error", "failing"].includes(w.status));
          if (!failed) { out({ status: "success", pipelineNumber: p.number }); return; }
          out({ status: "failed", pipelineNumber: p.number, feedback: await failureFeedback(wfs) }); return;
        }
      }
      await sleep(8); waited += 8;
    }
    out({ status: "timeout", feedback: `CI did not finish within ${maxWaitSec}s` });
  } catch (e) { out({ status: "error", feedback: e.message }); }
})();
