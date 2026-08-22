# scripts

Interactive entry points — one per article. Each loads its analytics library and
data generator, builds a synthetic scenario, and leaves a few named globals in the
workspace for exploring at the `q)` prompt. Neither script takes parameters; run
from the repo root.

## Structure

| File | Run | Loads |
|---|---|---|
| `initMarkout.q` | `q scripts/initMarkout.q` | `analytics/markOutImpact.q`, `data/generator.q` |
| `initSpread.q` | `q scripts/initSpread.q` | `analytics/spread.q`, `data/spreadGenerator.q` |

Both follow the same shape: a local `init` function does the loading and scenario
building, assigns its results to **global** variables (`::`, since the assignments
happen inside a function), then calls itself once at the bottom of the file so the
globals exist by the time the script finishes loading.

## `initMarkout.q`

Builds a 6-hour synthetic EURUSD session (`.synth.buildScenario[]`) with five known
market-impact events baked in, and leaves:

| Global | Contents |
|---|---|
| `scenario` | dict of `rate`/`trades`/`orders`/`groundTruth` — the synthetic session |
| `markout` | `.markout.calc` run over `scenario`'s trades against its rate series |
| `impact` | recovered temp/perm impact per order (`.impact.calc`+`.impact.decompose`) compared against the injected ground truth |

## `initSpread.q`

Builds a synthetic 6,000-quote session (`.spreadSynth.genSession`, 3,000 per
regime) across 3 symbols and 3 aggression levels, with a `normal`→`stressed`
transition and a known benchmark-richness offset baked in, and leaves:

| Global | Contents |
|---|---|
| `scenario` | dict of `quotes`/`benchmark`/`groundTruth` — the synthetic session |
| `recovery` | `.spread.wavgBy`/`.spread.vsReference` output checked against the injected ground truth (stress-volatility multiplier, benchmark richness) |
| `byRegime` | spread build-up weight-averaged by aggression × market status |
| `byTime` | spread build-up weight-averaged by minute, independent of `byRegime`'s check |

## Interactive use vs. `test/`

These scripts are for exploring at the console — nothing here asserts or exits
non-zero on a wrong answer. [`test/`](../test/) covers that: `test/testSpread.q` runs
the same kind of checks as hard pass/fail assertions, suitable for CI. There's no
`test/testMarkout.q` yet — `initMarkout.q`'s `impact`/`markout` globals are the only
way to eyeball that article's recovery today.
