# perf

Performance benchmarks for the analytics libraries — a shared, functions-only timing
harness plus one runner per article, each timing every public function in its own
`analytics/*.q` file against realistic-sized synthetic data.

## Structure

| File | Purpose |
|---|---|
| `perfChk.q` | shared harness — no article knowledge, functions only. Loaded by both runners below. |
| `perfMarkOut.q` | times every `.util.*`/`.markout.*`/`.impact.*` function from `analytics/markOutImpact.q` |
| `perfSpread.q` | times every `.spread.*` function from `analytics/spread.q` |

Run either directly:

```bash
q perf/perfMarkOut.q
q perf/perfSpread.q
```

Each runner loads its analytics file, its data generator (`data/generator.q` /
`data/spreadGenerator.q`), and `perfChk.q`; builds its own benchmark dataset at 5x the
size used in the articles' interactive scenarios; times every function; and prints a
`.perf.results` table before exiting.

## `perfChk.q` — the harness

| Function | Purpose |
|---|---|
| `.perf.results` | the output table: `section`, `label`, `reps`, `avgMs`, `totalMs`, `kb`, `error` |
| `.perf.priv.run` | time one q expression (given as a string) over `n` reps via kdb+'s built-in `\ts` time+space profiler, called programmatically as `` system"ts do[n;expr]" `` so the `(ms;bytes)` pair can be captured and averaged rather than only printed. A runtime error inside the expression is caught and recorded as a failed row (null timings, message in `error`) instead of aborting the whole run. |
| `.perf.report` | widen the console and print `.perf.results` |
| `.perf.priv.seedPending` | reset a global keyed pending-table to empty, then call an `onX` function once per row built from `til n` — the "seed N distinct pending entities" step shared by every bulk-drain benchmark below |

**Why some functions can't just be looped.** Pure/batch functions (`compose`,
`wavgBy`, `calc`, …) are safe to call `n` times in a row and average — `.perf.priv.run`
does exactly that. The real-time-path functions that *drain* a pending table on a
match (`onRate`, `onBook`, `sweepPending`) are not: a second identical call would
measure an empty-hits no-op, not the real cost. Both runners instead seed several
hundred distinct pending rows via `.perf.priv.seedPending`, then time a *single* call
that completes/evicts all of them at once — a realistic bulk-tick cost rather than a
meaningless repeated-drain average.

## `perfMarkOut.q` — dataset & sections

Rebuilds `data/generator.q`'s `.synth.buildScenario` shape at 5x scale from the
lower-level `.synth.*` pieces (it takes no size parameters itself): a 30-hour EURUSD
session at 0.5s ticks (~216,000 rate ticks), 10,000 trades, 25 orders.

| Section | What's timed |
|---|---|
| `util` | `buildGrid`, `toTimespan`, `explode` — the shared offset-grid plumbing |
| `markout.batch` | `calc`, `calcDate`, `calcAll`, `notionalWeighted` |
| `markout.rt` | `onTrade` (steady-state upsert), `onRate` (bulk drain of 500 pending trades' grids), `sweepPending` (bulk eviction of 500) |
| `impact.batch` | `calc`, `decompose`, `bySymSide` |
| `impact.rt` | `onOrder`, `onBook` (bulk drain of 500), `sweepPending` (bulk eviction of 500) |

Note printed with the report: `.markout.calcAll` uses `peach`, which degrades to
sequential `each` in a single process (no `-s N`) — its number reflects sequential
cost, not parallel speedup.

## `perfSpread.q` — dataset & sections

Uses `data/spreadGenerator.q`'s `.spreadSynth.genSession` directly at 5x scale:
30,000 quotes plus a matching independent benchmark series.

| Section | What's timed |
|---|---|
| `spread.compose` | `compose`, `decompose`, `waterfall` |
| `spread.agg` | `priv.wavgAggCols`, `wavgBy`, `util.timeBucket`, `byTime`, `byRegime`, `shareByTime`, `priv.wpctl`, `pctlBy`, `pctlByTime` |
| `spread.recon` | `vsReference` |
| `spread.rt` | `onQuote`, `latest` |

See the [spread article](../articles/spread/spreadAnalytics.md#appendix-performance)
for the resulting numbers and their interpretation (why `compose` is nearly free,
why the percentile rollups cost ~3.5x their `wavg` counterparts, why `shareByTime`
costs almost nothing on top of `byTime`, and so on).
