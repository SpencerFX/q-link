## Running the code for "Logging Isn't Just print — It's a Table"

From the repo root:

```bash
q scripts/initLogging.q
```

This loads `.logToTab.*` (`sre/logToTab.q`), opens a listening port and defines a
`logs` table + `upd:insert` in the *same* process (standing in for what would
normally be a separate mon process — see the script's header comment for why that's
a fair stand-in), connects `logToTab.q` back to it over a loopback handle, and drips
in a small pricing-service scenario at a mix of levels: a connect, a lagging feed, a
rejected quote, a recovery. It leaves three globals in the workspace:

- `logs` — the mon-side table every message landed in, live
- `logsSnapshot` — `0!logs`, a plain (unkeyed) snapshot for `select`/`exec` at the console
- `ringSnapshot` — `0! .logToTab.tab`, this process's own local ring buffer

To run the same checks as hard pass/fail assertions instead (suitable for CI):

```bash
q test/testLogToTab.q
```

To see what these functions cost:

```bash
q perf/perfLogToTab.q
```

```
q)logsSnapshot
timestamp                     sym       level host       pid  handle user message
-----------------------------------------------------------------------------------------------------------------------
2026.08.24D10:23:30.097321200 pricingSvc INFO  giantsteps 9364 0     ...   "connected to rate feed EURUSD"
2026.08.24D10:23:30.097495300 pricingSvc WARN  giantsteps 9364 0     ...   "rate feed lagging 850ms behind wall clock, buffering"
2026.08.24D10:23:30.097520100 pricingSvc ERROR giantsteps 9364 0     ...   "quote for EURUSD rejected: rate is 3200ms stale"
2026.08.24D10:23:30.097533000 pricingSvc INFO  giantsteps 9364 0     ...   "rate feed caught up, quoting resumed"
```

Six rows land in `logs` by the end of the run even though only four print to the
console — the DEBUG line and the INFO line logged after the script raises the
console threshold to WARN are both still in `logs` and `ringSnapshot`, just not on
screen. That gap is the entire point of the library: the console threshold controls
what scrolls past you right now, not what's queryable later.
