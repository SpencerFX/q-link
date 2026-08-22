# test

Non-interactive test suites — hard pass/fail assertions, suitable for CI. Unlike
[`scripts/`](../scripts/) (which builds a scenario and leaves it in the workspace to
eyeball), these throw on the first failing assertion and exit non-zero.

## Structure

| File | Run | Covers |
|---|---|---|
| `testMarkOutImpact.q` | `q test/testMarkOutImpact.q` | every public function in `analytics/markOutImpact.q` |
| `testSpread.q` | `q test/testSpread.q` | every public function in `analytics/spread.q` |

## How `testMarkOutImpact.q` is built

Same `.test.assert` pattern as `testSpread.q` below. Most checks are built to be
**exact**, not approximate, by exploiting how `aj` (as-of join) works: a hand-built
trade/order plus just **two** rate/book ticks — one placed well before every
negative-offset target, one placed exactly at the anchor time — deterministically
matches *every* row across the real ~61-point `.markout.gridSecs` /
`.impact.gridSecs` grid (negative offsets always match the early tick, non-negative
offsets always match the at-anchor tick), so the whole grid's `markoutVal`/`impact`
and `stale` columns can be asserted exactly without needing a large synthetic
dataset.

| # | What's checked | Against |
|---|---|---|
| 1–2 | `buildGrid`/`toTimespan`: exact mirrored grid construction and timespan casts | hand-built inputs |
| 3 | `explode`: `targetTime` is anchor + offset, exactly, one row per grid point | a 1-row table crossed with a 3-point grid |
| 4 | `markout.calc`: every one of the real ~61 grid rows matched (no nulls), `markoutVal` and `stale` exact for every offset | the two-tick trick, against the real `.markout.gridSecs` |
| 5 | `notionalWeighted`: exact notional-weighted bps at one bucket; an all-stale bucket is absent from the output, not null | 2 hand-built trades, opposite-sign markout, different notionals |
| 6–7 | `onTrade`/`onRate`/`sweepPending`: pending/completed counts exactly match `.markout.gridSecs`/`.markout.pendingTTL`, derived dynamically (not hardcoded) so the test stays correct if the grid changes | fresh real-time state |
| 8 | `impact.calc`: every grid row matched; buy/sell sign-normalization is an exact negation for the same market move | the two-tick trick, buy + sell orders |
| 9 | `decompose`: `temporaryImpact`/`permanentImpact` are the exact max-within-window / avg-beyond-window | a hand-built impact curve |
| 10 | `bySymSide`: `meanImpactBps` is exactly `1e4*avg(impact)` for one bucket | 2 hand-built rows |
| 11–12 | `onOrder`/`onBook`/`sweepPending`: same dynamically-derived exactness as markout's real-time checks | fresh real-time state, `.impact.gridSecs`/`.impact.pendingTTL` |
| 13 | Synthetic ground truth: `.synth.buildScenario`'s five injected impact events recovered in the right order (`temporaryImpactBps > permanentImpactBps`) and right order of magnitude by `.impact.decompose` | `data/generator.q`, this build's fixed default RNG seed |
| 14 | A driftless (`mu=0`) rate series' batch markout mean at the max offset is statistically indistinguishable from zero (within 4 self-computed standard errors) | 500 synthetic trades |

Check #13 is deliberately loose (order-of-magnitude, not a tight relative-error
bound): each injected event is a *single* order riding one noisy GBM path, so
there's no law-of-large-numbers smoothing the way there is for check #14's 500
trades — per-event relative error on a few-bps ground truth is genuinely noisy
(observed up to ~110% on this codebase's fixed default RNG seed), and a tight bound
here would be testing sampling luck, not correctness.

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
