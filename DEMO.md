# Demo: Chunk Sidecars — Validation moves left

A 4-minute live stage demo. Built for LeadDev LDX3 London (June 2026), reusable for any inner-loop / shift-left story.

---

## The story

**Setup the audience:**

> AI agents are now writing a meaningful chunk of every team's code. They're fast.
> They're also unvalidated. Every speculative test failure, every dead import, every
> half-finished refactor — gets pushed to CI, where the team's pipelines pay for it.
> CI minutes spike. PR queues lengthen. Engineers wait.

**The framing question:**

> What if we moved validation *left* — into the agent's own inner loop — so the
> same checks CI runs ran *before* anything got committed?

That's Chunk Sidecars.

---

## What you'll see (3 acts)

### Act 1 — The setup
The agent has just made what looks like a reasonable change to a Payments screen. It added a welcome line, tweaked the title copy, started a refactor by importing `TouchableOpacity`. To a reviewer skimming the diff, this looks shippable.

### Act 2 — The sidecar bites
The same gates CI runs — install, lint, test, bundle — run locally in the sidecar. **In about seven seconds**, the sidecar surfaces the first problem. The agent fixes it. Sidecar runs again. Surfaces the next problem. Agent fixes that. Sidecar runs again. Green.

Two iterations, end-to-end under a minute. The agent never touched the network. CI was never asked to do unpaid labour.

### Act 3 — The handshake
The agent pushes the change. The real CircleCI pipeline runs the same checks the sidecar just ran. Pipeline goes green. **First push, first pass.**

The point is simple: when validation lives where the agent works, CI stops being a debugger and goes back to being a release pipeline.

---

## On-stage runbook

### Pre-flight (do these before the talk, never live)

```bash
# 1. Working tree is clean and on main
cd ~/projects/mobile/circleci-mobile-banking-app
git status                                 # should be clean
git pull --ff-only origin main

# 2. Sidecar is active and healthy
chunk sidecar current                      # should show circleci-mobile-banking-app
chunk validate --list                      # should show all 8 gates

# 3. Warm the sidecar (cold first run is slower — do it now, not on stage)
chunk validate                             # expect green in ~15s

# 4. Apply the broken state
./scripts/seed-broken.sh

# 5. Open in your editor with these files visible:
#    - miniapps/payments/src/App.js  (the broken file)
#    - miniapps/payments/__tests__/App.test.js (the test that'll fail)
#    Have Claude Code open in a terminal pane.

# 6. Verify the broken state actually fails (sanity check)
chunk validate                             # expect lint-payments to fail in ~7s
```

You're now ready. **Don't `chunk validate` again pre-stage** — you want to fail live, not show a cached failure scrolling past.

---

### Stage beats

#### Beat 1 — Frame the problem (0:00 → 0:30)

Slide or just speak:

> AI agents push fast, and what they push is often broken. CI catches it eventually — but eventually is too late. What if CI's checks moved closer to the agent?

Don't dwell. The audience came for the demo, not a manifesto.

#### Beat 2 — Show the broken change (0:30 → 1:00)

Open `miniapps/payments/src/App.js` in the editor. Audience sees:

```javascript
import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';

const App = () => (
  <View style={styles.container}>
    <Text style={styles.welcome}>Welcome back</Text>
    <Text style={styles.title}>Welcome to Payments</Text>
  </View>
);
```

Say:

> Claude was asked to make the Payments screen feel more welcoming. Here's what it produced. Added a welcome line, updated the title, imported `TouchableOpacity` for some interactivity it never finished wiring up. To a human reviewer skimming this, it looks fine.

#### Beat 3 — First validation, lint catches it (1:00 → 1:30)

In Claude Code, type:

> Validate my recent changes.

Claude finishes its turn → **Stop hook auto-runs `chunk validate`** → output shows:

```
Running install-payments ✓
Running install-transfers ✓
Running lint-payments ✗
  'TouchableOpacity' is defined but never used  no-unused-vars

⚠ test-payments: skipped (lint-payments failed)
⚠ bundle-payments: skipped (lint-payments failed)
```

Say:

> Seven seconds. The sidecar ran the exact same lint check CI runs, on the same code, and caught the dead import.

#### Beat 4 — Claude fixes the lint error (1:30 → 1:50)

Claude — having seen the hook output — proposes:

```diff
- import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
+ import { View, Text, StyleSheet } from 'react-native';
```

Accept the fix.

#### Beat 5 — Second validation, test catches it (1:50 → 2:30)

Stop hook fires again. Now:

```
Running install-payments ✓
Running install-transfers ✓
Running lint-payments ✓
Running lint-transfers ✓
Running test-payments ✗
  Unable to find an element with text: Payments
  > expect(getByText('Payments')).toBeTruthy();
```

Say:

> Lint passes now. But the test still expects the old title text. The agent never updated the assertion.

#### Beat 6 — Claude fixes the test (2:30 → 2:50)

Claude proposes either:
- Update the test to assert `'Welcome to Payments'`, **or**
- Revert the title back to `'Payments'`

Either is a real engineering decision. For the demo, accept the test update — it matches the agent's stated intent ("make it more welcoming").

#### Beat 7 — Sidecar goes green (2:50 → 3:10)

Stop hook fires. All 8 gates green in ~15s.

```
✓ install-payments
✓ install-transfers
✓ lint-payments
✓ lint-transfers
✓ test-payments
✓ test-transfers
✓ bundle-payments
✓ bundle-transfers
```

Say:

> Two iterations. Under a minute total. The agent never touched CI.

#### Beat 8 — Push and watch CI agree (3:10 → 4:00)

```bash
git add miniapps/payments/
git commit -m "feat(payments): add welcome message"
git push
```

Switch to the CircleCI tab. The pipeline runs the same install / lint / test / bundle checks the sidecar ran, in parallel for both miniapps. Goes green.

Closing line:

> When the sidecar agrees, CI agrees. First push, first pass. That's what validating in the inner loop actually buys you.

---

### Recovery moves (if something goes sideways)

| Symptom | Most likely cause | What to do live |
|---|---|---|
| `chunk validate` hangs >30s | Sidecar lost its session | Run `chunk sidecar current` to confirm, then `chunk validate` again. Worst case: switch to the local fallback below. |
| Lint passes but you needed it to fail | `seed-broken.sh` wasn't run pre-flight | Quietly run `./scripts/seed-broken.sh` while talking, then re-run validate. |
| Stop hook doesn't fire | `.claude/settings.json` not loaded | Run `chunk validate` manually in another terminal pane — narrate it the same. |
| Claude fixes both at once in one turn | The "two iterations" beat collapses to one | Just lean into it: "Even faster than expected. Two issues, one pass." |
| CI takes >2 minutes | Cold runner / cache miss | Have a screenshot of a previous green run ready; pivot to "and you can see in a previous run…" |

### Local-only fallback (no network)

If the sidecar is unreachable, the same gates run locally:

```bash
(cd miniapps/payments && npm run lint && npm test -- --watchAll=false)
```

Same output, same story. Just lose the "sidecar matches CI environment" beat.

---

## Reset between runs

```bash
./scripts/reset-clean.sh             # restores App.js AND App.test.js
chunk validate                       # confirm green baseline (~13s)
./scripts/seed-broken.sh             # re-seed for the next run
```

---

## Reusing this demo

This whole repo is a reusable demo artifact. To build your own variant:

1. Edit `scripts/seed-broken.sh` to change *what* the agent "did wrong" — different feature, different bug class.
2. Edit `.chunk/config.json` to change which gates run.
3. Edit this `DEMO.md` to match.

Keep the baseline green on `main` so anyone can clone, seed, and run.
