# Chunk Sidecars — Live Demo Script
### LeadDev LDX3 London · ~6 minutes

---

## PRE-FLIGHT (run backstage before the talk)

```bash
cd ~/projects/mobile/circleci-mobile-banking-app    # the demo repo
git status                                          # confirm clean main
chunk sidecar current                               # confirm sidecar is up
chunk validate                                      # warm it (green in ~13s)
./scripts/seed-broken.sh                            # apply the broken-agent state
claude                                              # launch Claude Code from inside the repo (so the Stop hook activates)
```

**Have open before you go on stage:**
- Editor with `miniapps/payments/src/App.js` visible (left half of screen)
- A second editor tab with `.chunk/config.json` and `.circleci/config.yml` side by side (for the contract beat)
- Claude Code terminal (right half of screen)
- Browser tab pre-loaded to your CircleCI pipeline page

> ⚠️ Do not run `chunk validate` again after seeding — the first failure needs to happen live.

---

## INTRO (0:00 → 0:30)

> **[Face the audience. No commands yet.]**

AI coding agents are fast. Really fast. Claude Code, Cursor — they ship code at a pace no developer could match manually.

But fast doesn't mean correct.

A lot of the time the problem isn't that agents write bad code. The problem is that by the time CI tells you something is broken — the agent has moved on. The context is gone. You're debugging a change from the agent you've already forgotten.

What if validation happened *before* the commit? Before the push. Before CI even sees it.

That's what Chunk Sidecars do. And I'm going to show you exactly how it works.

---

## WHAT IS THE INNER LOOP? (0:30 → 1:15)

> **[Image on screen: the two-loop diagram — Inner Loop (Plan → Code → Validate → Debug) on the left, Outer Loop (Build → Test → Deploy → Release) on the right, joined by "Change" and "Feedback" arrows.]**

Quick bit of framing. Every change lives in two loops.

The **inner loop** — on the left — is where you actually work: plan, code, validate, debug, on your machine, in seconds. The **outer loop** — on the right — is what happens after you push: build, test, deploy, release, in CI, in minutes.

For years those were balanced. Then AI showed up and made the inner loop incredibly fast — but not any more *correct*. So incomplete changes sail through the inner loop and pile up in the outer loop, where every failure costs a full CI cycle and a context switch.

> **[Point to the "Validate" node on the inner-loop side.]**

The fix isn't a faster outer loop. It's putting real validation back *here* — on the Validate step, inside the inner loop — so a change is correct before it ever becomes CI's problem.

That's the gap sidecars close.

---

## WHAT IS A SIDECAR? (1:15 → 1:45)

> **[Optional: switch to terminal, run `chunk sidecar current` and `chunk validate --list`]**

A sidecar is a remote sandbox — running on CircleCI — that mirrors your CI environment exactly. Same install commands. Same lint rules. Same test suite.

It lives next to your editor, not at the end of a pull request.

> **[Point to the list of gates if visible]**

Here's mine. Twelve gates — install, lint, **scan**, test, build — across both mini-apps. Trivy and Snyk run alongside the unit tests, so a transitive CVE blocks the agent the same way a failing test does. Same commands my CircleCI pipeline runs. The difference is *when* they run.

---

## THE CONTRACT — SIDECAR ≡ CI (1:45 → 2:45)

> **[Switch to the editor tab with `.chunk/config.json` and `.circleci/config.yml` side by side.]**

People hear "runs on a sidecar" and assume it's an approximation — a linter that's *close* to CI's, tests that are *mostly* the same. That gap is exactly where "works on my machine" lives.

So look at this. On the left, `.chunk/config.json` — what the sidecar runs. On the right, `.circleci/config.yml` — what CI runs.

> **[Point to the Snyk gate in each.]**

The sidecar's `scan-payments-snyk` gate:

```
cd miniapps/payments && snyk test --severity-threshold=high
```

The CircleCI step, *Scan: Snyk (severity high+)*:

```
cd miniapps/payments && snyk test --severity-threshold=high
```

Character for character, the same command. Same for Trivy — `trivy fs --severity HIGH,CRITICAL --exit-code 1` in both. Same install, same lint, same test, same bundle.

This isn't *similar* to CI. It **is** CI's command set, pulled forward to the inner loop. One contract, two places it runs. When the sidecar is green, there's no daylight left for CI to find.

---

## WHAT IS A STOP HOOK? (2:45 → 3:15)

Here's the part that makes this interesting. I'm not going to type `chunk validate` once during this demo.

Claude Code has a feature called a **Stop hook** — a shell command that fires automatically every time the agent finishes a turn. You configure it once, in `.claude/settings.json`. When you run `chunk init` in your repo, it generates that file for you.

It looks like this:

```json
"hooks": {
  "Stop": [
    { "hooks": [{ "type": "command", "command": "chunk validate" }] }
  ]
}
```

That's it. Every time Claude finishes a reply — the sidecar runs. If something fails, that failure is injected back into the conversation. Claude sees it. Claude fixes it. Before anything is pushed.

> **[Pause. Let that land.]**

Validation in the inner loop. Not as an afterthought. As part of the agent's lifecycle.

---

## THE DEMO (3:15 → 4:55)

> **[Screen: editor on left showing `miniapps/payments/src/App.js`, Claude Code terminal on right]**

Here's the scenario. I asked Claude to make the Payments screen feel more welcoming. It added a welcome line, updated the title, started importing `TouchableOpacity` for some interactivity it never finished.

To a human skimming the diff — this looks shippable. Let's see what the sidecar thinks.

> **[Switch to Claude Code terminal. Type:]**

```
Quick sanity check on the Payments changes before I push?
```

> **[Claude replies. Stop hook fires automatically. ~7 seconds later:]**

```
✗ lint-payments
  'TouchableOpacity' is defined but never used  no-unused-vars
```

Seven seconds. Dead import. Same lint rule CI would have caught — just minutes earlier, and zero pipeline spend.

> **[Type:]**

```
go ahead
```

> **[Claude removes the unused import. Stop hook fires again. ~9 seconds later:]**

```
✗ test-payments
  Unable to find an element with text: Payments
```

Lint passes. But the test is still asserting the old title. The sidecar caught the second issue on the next turn — no prompt needed.

> **[Type:]**

```
go ahead
```

> **[Claude updates the test. Stop hook fires. ~30 seconds later, all 12 gates green — install, lint, scan, test, bundle.]**

Two fixes. Under a minute. The agent never touched CI. And the scan gates went green alongside the tests — vulnerability checking happens in the same loop, not as a separate PR check that runs hours later.

---

## THE PUSH (4:55 → 5:45)

> **[In the terminal, type:]**

```bash
git add miniapps/payments/
git commit -m "feat(payments): add welcome message"
git push
```

> **[Switch to the CircleCI pipeline tab in the browser. Pipeline runs. Goes green.]**

When the sidecar agrees — CI agrees.

First push. First pass. No pipeline failures. No re-runs. No context switching.

> **[Face the audience.]**

That's what validation in the inner loop looks like. Not faster machines. Not more parallelism. Just the right answer, at the right moment — before it costs you anything.

That's Chunk Sidecars.

---

## ANTICIPATED QUESTIONS

**"How does it know to run after every turn?"**
One command — `chunk init` — wires it up. It generates `.claude/settings.json` with the Stop hook pointing at `chunk validate`. You don't write the file by hand.

**"What if the sidecar and CI disagree?"**
They run the same commands. `.chunk/config.json` and `.circleci/config.yml` are the same gates. We treat them as one contract.

**"Doesn't this slow every Claude turn down?"**
By about 20–30 seconds on turns that change code, on a warm sidecar (scans add a few seconds; the vuln DBs are pre-cached on the sidecar snapshot). That's CI's job — including security scanning — done in seconds instead of minutes, once per turn rather than once per PR.

**"Why two scanners?"**
Trivy and Snyk catch overlapping but not identical CVEs — Trivy reads the package-lock and matches against the Aqua advisory DB; Snyk does graph-aware analysis with its own DB. Running both is cheap on a warm sidecar (~5–10s combined) and the union of findings is broader than either alone.

---

## IF SOMETHING GOES WRONG

| What happened | Do this |
|---|---|
| `chunk validate` hangs past 30s | Run `chunk sidecar current` in another pane. If healthy, retry. Otherwise fall back: `cd miniapps/payments && npm run lint && npm test` |
| Stop hook didn't fire | You launched Claude Code from outside the repo. Quit, `cd` into the repo, run `claude` again |
| Claude caught the bug in its first reply | Pivot: *"Even better — but what about the test?"* Send message 2 to continue |
| CI takes longer than 2 minutes | Have a screenshot of a previous green run ready. *"In a previous run, you can see…"* |

---

## RESET BETWEEN RUNS

```bash
./scripts/reset-clean.sh
git reset --hard origin/main
```

Then re-run pre-flight from the top.
