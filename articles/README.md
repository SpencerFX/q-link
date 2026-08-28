## Articles

| Article | Code |
|---|---|
| [From Markout to Market Impact](articles/markout/markOutImpact.pdf) — client deal markout vs. order/execution impact, and why both are the same computational shape underneath | `analytics/markOutImpact.q`, `data/generator.q`, `scripts/initMarkout.q` |
| [Explaining the Spread](articles/spread/spreadAnalytics.md) — decomposing a quoted FX spread into named pricing components, and why aggregating that decomposition correctly matters more than estimating it | `analytics/spread.q`, `data/spreadGenerator.q`, `scripts/initSpread.q` |
| [Logging Isn't Just print — It's a Table](articles/logging/loggingSRE.md) — a leveled logger that forwards into a shared `logs` table instead of (or alongside) a scrolling console, so an incident across several processes is one query instead of N log files | `sre/logToTab.q`, `scripts/initLogging.q` |