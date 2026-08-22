# test

Non-interactive test suites — hard pass/fail assertions, suitable for CI. Unlike
[`scripts/`](../scripts/) (which builds a scenario and leaves it in the workspace to
eyeball), these throw on the first failing assertion and exit non-zero.

## Structure

| File | Run | Covers |
|---|---|---|
| `testSpread.q` | `q test/testSpread.q` | every public function in `analytics/spread.q` |

There's no `testMarkout.q` yet — `analytics/markOutImpact.q`'s correctness today is
only checked interactively via `scripts/initMarkout.q`'s `markout`/`impact` globals.

## How `testSpread.q` is built

`.test.assert:{[msg;cond] if[not cond;'"FAILED: ",msg]; -1"PASSED: ",msg;}` — on
failure, `'` signals a q error (non-zero exit, stack trace on stderr, first failure
stops the run); on success it prints and moves on. The file prints
`ALL TESTS PASSED` and `exit 0`s only if every assertion below it passed.

Each check picks the smallest input that can prove the property, rather than
reusing one big scenario throughout:

| # | What's checked | Against |
|---|---|---|
| 1 | `compose`: `totalSprd` is the exact row-wise sum | a 2-row hand-built table (`toy`), checked to 1e-9 |
| 2 | `waterfall`: `cum_alphaSprd == totalSprd` on every row | `toy` |
| 3 | `decompose`: `componentValue` sums back to `totalSprd` per row | `toy` |
| 4 | `byRegime`: a single-row group's weighted avg equals that row's value | `toy` (n=1 per group) |
| 5 | `vsReference`: `richnessBps == 1e4*(totalSprd-benchmarkSprd)` exactly | a hand-built reference row |
| 6 | `priv.wpctl`: nearest-rank percentile lands on the correct (heavier) row | `toy`'s two rows, weights 1e6/2e6 |
| 7 | `pctlBy`/`pctlByTime`: `p50 <= p90 <= p99` in every group/bucket | a 2,000-quote synthetic session |
| 8 | `compose`/`waterfall`/`decompose` all work on a **keyed** source (e.g. `byTime`'s own output), not just raw unkeyed quotes | `toy`, rolled up by `byTime` first |
| 9 | Synthetic ground-truth recovery: injected `stressVolMult` and `richnessBps` both recovered within tolerance | `.spreadSynth.genSession`/`.spreadSynth.checkRecovery`, 6,000 quotes |
| 10 | `shareByTime`: `pctOfTotal` sums to exactly 100 per bucket, and `volSprd`'s share is higher in the stressed regime than the normal one | the same synthetic session as #9 |

Check #8 exists because of a real bug class in this codebase: bracket/`#` access on
a keyed table means "look up this key value," not "get this column," so any function
written against a plain table can silently break the moment it's fed another
function's keyed output — `compose`, `waterfall`, and `decompose` all had exactly
this bug at one point, which is why the regression test pins it down explicitly
rather than trusting it stays fixed.
