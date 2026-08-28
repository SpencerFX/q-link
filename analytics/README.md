# analytics

The kdb+/q analytics libraries themselves — one file per article, plus a real-time
topology (`core/`) that runs both libraries live instead of over a synthetic batch.

## Structure

| Path | Purpose |
|---|---|
| `markOutImpact.q` | `.util.*` / `.markout.*` / `.impact.*` — client deal markout vs. order/execution market impact. See [From Markout to Market Impact](../articles/markout/markOutImpact.pdf). |
| `spread.q` | `.spread.*` — FX quote spread composition, decomposition, weighted aggregation, percentile/distribution analysis, and reconciliation vs. a reference. See [Explaining the Spread](../articles/spread/spreadAnalytics.md). |
| `core/` | A from-scratch tickerplant → rdb / cep topology that runs both libraries above against a live tick stream instead of a one-shot batch. See [`core/README.md`](core/README.md). |

## How they relate

`markOutImpact.q` and `spread.q` are each self-contained and can be loaded and used
on their own — that's what `scripts/initMarkout.q` / `scripts/initSpread.q` and the
articles in [`../articles/`](../articles/) do, against a synthetic batch built by
`data/generator.q` / `data/spreadGenerator.q`.

`core/` doesn't reimplement any analytics — `core/cep.q` just loads both files
unchanged and routes live ticks into the exact same real-time entry points
(`.markout.onTrade`/`.onRate`, `.impact.onOrder`/`.onBook`, `.spread.onQuote`) that
each library already exposes for incremental use. The batch and real-time paths are
two different callers of the same code, not two implementations.

## Function reference

See the root [`README.md`](../README.md#function-reference) for the full
namespace/function table of `markOutImpact.q` and `spread.q`.
