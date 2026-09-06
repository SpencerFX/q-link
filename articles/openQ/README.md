## About "A New Module Is Six JSON Files"

Unlike this repo's other articles, there's no `q` script to run here —
`openQ` is a separate project at
[SpencerFX/openQ](https://github.com/SpencerFX/openQ), the author's
domain-generic kdb+ tick-database core. This piece documents its
*architecture*, not any one module's business logic (those already have
their own pieces — [`spread`](../spread/spreadAnalytics.md),
[`markout`](../markout/markOutImpact.pdf),
[`primeFinance`](../primeFinance/primeFinance.md),
[`openDash`](../openDash/openDash.md)): the six schema-agnostic
steady-state roles (`tp`/`cep`/`rdb`/`idb`/`hdb`/`gw`), the config-driven
bootstrap that lets a module plug in as six JSON files and zero core code
changes, the RDB active/standby pair and the pivot-and-harvest design
that drives it, the atomic staged-write path every durable write goes
through, and the generic async gateway that fans a query out to however
many backends it actually needs.

Unlike `primeFinance`'s and `openDash`'s articles, **no process was
started, stopped, or queried to write this one** — the user asked
explicitly that nothing currently running be touched. Every claim and
code excerpt here comes from reading the real source and config on disk,
not from a captured live run; there's no performance appendix and no
"live state" section as a result, and the article's own Known
limitations section says this plainly rather than implying a rigor it
didn't apply this time.

Read the article: [`openQ.md`](openQ.md).
