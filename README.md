# q-link

Code companion repository for my LinkedIn articles on kdb+/q. Each article gets a writeup in
[`articles/`](articles/) and runnable code to back it up, so readers aren't just taking the
post's word for it — they can pull the repo and reproduce every number and chart themselves.

## Articles

| Article | Code |
|---|---|
| [From Markout to Market Impact](articles/markout/markOutImpact.pdf) — client deal markout vs. order/execution impact, and why both are the same computational shape underneath | `analytics/markOutImpact.q`, `data/generator.q`, `scripts/initMarkout.q` |
| [Explaining the Spread](articles/spread/spreadAnalytics.md) — decomposing a quoted FX spread into named pricing components, and why aggregating that decomposition correctly matters more than estimating it | `analytics/spread.q`, `data/spreadGenerator.q`, `scripts/initSpread.q` |
| [Logging Isn't Just print — It's a Table](articles/logging/loggingSRE.md) — a leveled logger that forwards into a shared `logs` table instead of (or alongside) a scrolling console, so an incident across several processes is one query instead of N log files | `sre/logToTab.q`, `scripts/initLogging.q` |
| [openDash: Bridging a Browser to kdb+ Over Async IPC](articles/openDash/openDash.md) — a Node.js gateway that correlates a kdb+ gateway's async, self-numbered replies over a pooled connection, rebuilds every browser query as a validated q literal, and fans one shared tick feed out to many WebSocket clients | *(separate project — see [`articles/openDash/README.md`](articles/openDash/README.md))* |
| [A Locate Isn't a Number — It's a Reservation](articles/primeFinance/primeFinance.md) — securities lending as a scored, constrained allocation problem, why a lender reference table is deliberately a plain join rather than a true kdb+ foreign key, and fee/risk calibration marked against real historical equity data instead of synthetic prices | *(separate project — see [`articles/primeFinance/README.md`](articles/primeFinance/README.md))* |

## Requirements

A working [kdb+/q](https://kx.com/) installation (`q` on your `PATH`).


## Layout

**From Markout to Market Impact**

| File | Purpose |
|---|---|
| `analytics/markOutImpact.q` | `.util.*` / `.markout.*` / `.impact.*` — the analytics library |
| `data/generator.q` | `.gbm.*` / `.synth.*` — synthetic GBM rate series + impact injection |
| `scripts/initMarkout.q` | entry point: loads both and builds a scenario |
| `test/testMarkOutImpact.q` | non-interactive test runner: hard assertions, exits non-zero on failure |
| `articles/markout/markOutImpact.pdf` | the article itself |

**Explaining the Spread**

| File | Purpose |
|---|---|
| `analytics/spread.q` | `.spread.*` — spread composition/decomposition/aggregation/reconciliation |
| `data/spreadGenerator.q` | `.spreadSynth.*` — synthetic quote generator with known ground truth |
| `scripts/initSpread.q` | entry point: loads both and builds a scenario, for interactive use |
| `test/testSpread.q` | non-interactive test runner: hard assertions, exits non-zero on failure |
| `articles/spread/spreadAnalytics.md` | the article itself |

**Logging Isn't Just print — It's a Table**

| File | Purpose |
|---|---|
| `sre/logToTab.q` | `.logToTab.*` — a leveled logger that writes locally and forwards into a shared `logs` table |
| `scripts/initLogging.q` | entry point: loads it, opens a loopback mon connection, runs a small demo scenario |
| `test/testLogToTab.q` | non-interactive test runner: hard assertions, exits non-zero on failure |
| `perf/perfLogToTab.q` | performance runner for `.logToTab.*` |
| `articles/logging/loggingSRE.md` | the article itself |

**primeFinance**

| File | Purpose |
|---|---|
| `articles/primeFinance/primeFinance.md` | the article itself |
| `articles/primeFinance/README.md` | pointer to where the code actually lives |

No code lives in this repo for this one — `primeFinance` is a module of
[openQ](https://github.com/SpencerFX/openQ); see the article for the design.

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

**`sre/logToTab.q`**

| Namespace | Function | Purpose |
|---|---|---|
| `.logToTab` | `write` | format + print a leveled banner line if it passes the console threshold, and record it into the local `.logToTab.tab` ring buffer unconditionally |
| `.logToTab` | `connect`, `log` | open (or lazily reopen) a connection to the mon process hosting `logs`; log locally via `write`, then forward the same message as one row, unconditionally, if connected |
| `.logToTab` | `setLevel`, `mem`, `row` | set the active console threshold; current heap usage in MB; build the flat, column-ordered tuple `.log` publishes |

## License

Apache 2.0 — see [`LICENSE`](LICENSE).
