# sre

Operational tooling — code aimed at the processes themselves, not at market data.
Sits alongside `analytics/` (which is the trading/pricing logic) rather than under
it, the same way `analytics/core/`'s tickerplant is infrastructure for *running*
the analytics rather than analytics itself.

## Structure

| Path | Purpose |
|---|---|
| `logToTab.q` | `.logToTab.*` — a leveled logger that writes locally (console banner + in-memory ring buffer) and forwards into a shared `logs` table over IPC, the same wire shape a tick.q feed handler uses to publish a trade. See [Logging Isn't Just print — It's a Table](../articles/logging/loggingSRE.md). |

## How it relates to the rest of the repo

`logToTab.q` is self-contained — no dependency on `analytics/`, `analytics/core/`,
or anything else in this repo — so it can be copied into any q process on its own.
`scripts/initLogging.q`, `test/testLogToTab.q`, and `perf/perfLogToTab.q` all run it
against a loopback connection rather than a second process, purely so each stays a
single runnable file; the wire protocol doesn't know or care that both ends happen
to be the same process in the demo.

## Function reference

See the root [`README.md`](../README.md#function-reference) for the full
namespace/function table of `logToTab.q`.
