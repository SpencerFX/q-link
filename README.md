# q-link

Code companion repository for my LinkedIn articles on kdb+/q. Each article gets a writeup in
[`articles/`](articles/) and runnable code to back it up, so readers aren't just taking the
post's word for it — they can pull the repo and reproduce every number and chart themselves.

## Articles

| Article | Code |
|---|---|
| [From Markout to Market Impact](articles/markout/markOutImpact.pdf) — client deal markout vs. order/execution impact, and why both are the same computational shape underneath | `analytics/markOutImpact.q`, `data/generator.q`, `scripts/initMarkout.q` |
| [Explaining the Spread](articles/spread/spreadAnalytics.md) — decomposing a quoted FX spread into named pricing components, and why aggregating that decomposition correctly matters more than estimating it | `analytics/spread.q`, `data/spreadGenerator.q`, `scripts/initSpread.q` |

## Requirements

A working [kdb+/q](https://kx.com/) installation (`q` on your `PATH`).

## Running the code for "From Markout to Market Impact"

From the repo root:

```bash
q scripts/initMarkout.q
```

This loads `.util.*`/`.markout.*`/`.impact.*` (`analytics/markOutImpact.q`) and the synthetic
data generator (`data/generator.q`), builds a synthetic 6-hour EURUSD session with five known
impact events baked in, and leaves three globals in the workspace:

- `scenario` — dict of `rate` / `trades` / `orders` / `groundTruth` (the synthetic session)
- `markout` — `.markout.calc` run over `scenario`'s trades against its rate series
- `impact` — recovered temp/perm impact per order compared against the injected ground truth

`impact` lines up the injected ground truth against what `.impact.decompose` recovered, per order:

![q)impact console output](articles/images/impact_table.png)

## Layout

```
analytics/markOutImpact.q       .util.* / .markout.* / .impact.* — the analytics library
data/generator.q                .gbm.* / .synth.* — synthetic GBM rate series + impact injection
scripts/initMarkout.q           entry point: loads both and builds a scenario
articles/markout/markOutImpact.pdf   the article itself

analytics/spread.q               .spread.* — spread composition/decomposition/aggregation/reconciliation
data/spreadGenerator.q           .spreadSynth.* — synthetic quote generator with known ground truth
scripts/initSpread.q             entry point: loads both and builds a scenario, for interactive use
test/testSpread.q                non-interactive test runner: hard assertions, exits non-zero on failure
articles/spread/spreadAnalytics.md   the article itself
```

## Function reference

**`analytics/markOutImpact.q`**

| Namespace | Function | Purpose |
|---|---|---|
| `.util` | `buildGrid`, `toTimespan`, `explode` | shared offset-grid plumbing used by both `.markout` and `.impact` |
| `.markout` | `calc`, `calcDate`, `calcAll` | batch markout, single-date and `peach`-across-dates wrappers |
| `.markout` | `notionalWeighted` | notional-weighted markout aggregated by sym/offset |
| `.markout` | `onTrade`, `onRate`, `sweepPending` | incremental/real-time path: register trades, complete offsets as rate ticks arrive, evict pending rows a dead feed never completed |
| `.impact` | `calc`, `decompose`, `bySymSide` | batch impact, temp/perm decomposition, mean impact curve by sym/side/offset |
| `.impact` | `onOrder`, `onBook`, `sweepPending` | incremental/real-time path, same shape as `.markout`'s |

**`data/generator.q`**

| Namespace | Function | Purpose |
|---|---|---|
| `.util.randNorm`, `.gbm.path` | — | Box-Muller normals and a GBM price path |
| `.synth.genRateSeries` | — | GBM mid-rate series for a sym over a session |
| `.synth.genTrades` | — | trades sampled off an existing rate series, for markout testing |
| `.synth.impactCurveBps`, `.synth.injectImpact(s)` | — | bake a known temp/perm decay signature into a rate series |
| `.synth.ordersFromSpec`, `.synth.getMid` | — | build the orders table matching injected impact events |
| `.synth.buildScenario` | — | one-call end-to-end scenario (rate + trades + orders + ground truth) |
| `.synth.checkImpactRecovery` | — | compare `.impact.decompose`'s recovered temp/perm against injected ground truth |

**`analytics/spread.q`**

| Namespace | Function | Purpose |
|---|---|---|
| `.spread` | `componentCols`, `quote` | the seven named components and the canonical input schema |
| `.spread` | `compose`, `decompose`, `waterfall` | row-wise sum to `totalSprd`; melt to one row per component; cumulative build-up columns |
| `.spread` | `wavgBy`, `byTime`, `byRegime` | weight-averaged rollup by arbitrary keys, by time bucket, or by caller-supplied regime columns — all three share `.spread.priv.wavgAggCols` |
| `.spread.util` | `timeBucket` | parse-tree for a `month`/`week`/`date`/`hour`/`minute`/`second` bucket, or a custom `xbar` timespan |
| `.spread` | `shareByTime` | each component's % share of `totalSprd`, tracked over time — `decompose` applied to `byTime`'s own output |
| `.spread` | `priv.wpctl`, `pctlBy`, `pctlByTime` | weighted percentiles (nearest-rank) of `totalSprd` by arbitrary keys or time bucket — the distributional counterpart to `wavgBy`/`byTime` |
| `.spread` | `vsReference` | reconcile the composed total against an independent reference/realized spread series, in bps and pct |
| `.spread` | `snap`, `onQuote`, `latest` | real-time path: keep the latest composed quote per (sym, aggression, marketStatus) key |

**`data/spreadGenerator.q`**

| Namespace | Function | Purpose |
|---|---|---|
| `.spreadSynth.priv.randNorm` | — | Box-Muller normals |
| `.spreadSynth.config.*` | — | the injected ground truth: aggression tightening multipliers, stress-volatility multiplier, benchmark richness offset |
| `.spreadSynth.genSession` | — | synthetic quote session, first half `normal`/second half `stressed`, with an independent benchmark series |
| `.spreadSynth.checkRecovery` | — | compare `.spread.wavgBy`/`.spread.vsReference`'s recovered values against the injected ground truth |

## License

Apache 2.0 — see [`LICENSE`](LICENSE).
