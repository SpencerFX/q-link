# data

Synthetic data generators — one per article, each building a session with **known
ground truth baked in**, so the corresponding `analytics/*.q` functions can be
checked against a right answer instead of eyeballed for plausibility. Neither file
depends on the other, or on anything outside base q, to run; each assumes its
matching `analytics/*.q` is already loaded for its demo/check section at the bottom.

## Structure

| File | Generates data for | Purpose |
|---|---|---|
| `generator.q` | `analytics/markOutImpact.q` | GBM mid-rate series + trades + orders, with a known temporary/permanent market-impact signature injected around chosen orders |
| `spreadGenerator.q` | `analytics/spread.q` | Synthetic spread quotes across symbols/aggression/market-status regimes, with a known volatility-stress multiplier and a known aggression-tightening factor injected |

## `generator.q`

| Namespace | Function | Purpose |
|---|---|---|
| `.util.randNorm` | — | standard-normal samples via Box-Muller (base q has no native Gaussian sampler) |
| `.gbm.path` | — | an n-step Geometric Brownian Motion price path |
| `.synth.genRateSeries` | — | GBM mid-rate series for a sym over a session |
| `.synth.genTrades` | — | trades sampled off an existing rate series (mid ± noise), for markout testing |
| `.synth.impactCurveBps`, `.synth.injectImpact(s)` | — | bake a known temp/perm decay signature into a rate series, at/after a chosen order time |
| `.synth.getMid`, `.synth.ordersFromSpec` | — | build the orders table matching the injected impact events, priced off the pre-injection baseline |
| `.synth.buildScenario` | — | one-call end-to-end scenario: `` `rate`trades`orders`groundTruth `` dict, a 6-hour EURUSD session with five well-separated impact events |
| `.synth.checkImpactRecovery` | — | run `.impact.calc`/`.impact.decompose` over the scenario and compare recovered temp/perm impact (bps) against the injected ground truth, side by side |

The injected ground truth: `.synth.buildScenario` plants five impact events
(alternating buy/sell, 40 minutes apart so their impact windows never overlap), each
with its own known `tempBps`/`permBps`/`halfLifeSecs`. A mild non-zero drift (`mu`)
on the baseline rate series also gives markout a checkable expected value (~`mu` ×
offset) rather than an unfalsifiable "should average to zero."

## `spreadGenerator.q`

| Namespace | Function | Purpose |
|---|---|---|
| `.spreadSynth.priv.randNorm` | — | Box-Muller normals |
| `.spreadSynth.config.*` | — | the injected ground truth: per-sym baseline spread level, aggression tightening multipliers, stress-volatility multiplier, benchmark richness offset |
| `.spreadSynth.genSession` | — | synthetic quote session, first half `` `normal ``/second half `` `stressed ``, plus an independent benchmark series with a known richness offset |
| `.spreadSynth.checkRecovery` | — | compare `.spread.wavgBy`'s recovered stress multiplier and `.spread.vsReference`'s recovered richness against the injected ground truth |

The injected ground truth: `volSprd` is multiplied by a known factor
(`stressVolMult`, default 4.0x) for every quote tagged `` `stressed ``, and
`baseSprd`/`clientSprd` scale by a known per-aggression-level multiplier — so both a
regime rollup (`.spread.byRegime`) and an independent time rollup (`.spread.byTime`)
should recover the same step. The `benchmark` series is built from `quotes`' own
composed `totalSprd` minus a known constant offset (`injectedRichness`) plus noise,
standing in for a rate the model didn't produce itself, for testing
`.spread.vsReference`.

## Why synthetic, not sampled

Both generators exist to make "is this function correct" a yes/no question rather
than a judgment call: a real spread or rate series has no known right answer to check
against, so every effect these generators produce (drift, impact decay, stress
multiplier, aggression tightening, benchmark richness) is specified as a config
constant first and recovered from the data second. Neither generator claims to model
how a real pricing engine or market actually behaves — see each article
([markout/impact](../articles/markout/markOutImpact.pdf),
[spread](../articles/spread/spreadAnalytics.md)) for what the numbers mean.
