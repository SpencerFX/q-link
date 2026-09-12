## About "Broker Tech: Retail FX and CFD Risk Analytics in kdb+/q"

Unlike this repo's other articles, there's no `q` script to run here.
`brokerTech` is a module of [openQ](https://github.com/SpencerFX/openQ),
the author's kdb+ trading platform, under `modules/analytics/brokerTech/`.
It is pure batch analytics over a real MetaTrader "Signals" copy trading
dataset (`C:/data/retail`), modelled on what a real FX/CFD broker risk
desk watches: exposure and concentration, execution quality, per client
profitability and drawdown, a five component toxicity score, A book / B
book routing recommendation, revenue attribution, risk threshold alerts,
and a from scratch, deterministically seeded k means client clustering
step. It is also wired into `openDash`, a separate Node.js gateway and
React frontend repo, as five live dashboard pages, two of which let a
desk analyst drag sliders and watch the routing and toxicity formulas
recompute instantly in the browser, seeded from the module's own live
config rather than a hardcoded guess.

Every number in the article came from running the module's own
`run.q` report against the real archive this session, at a real 180 day
window (167 active providers, 106,567 executed trades) and, for one
specific check, a wider 720 day window too. That wider check is what
keeps the piece honest: the module's own README claims IC Markets
accounts show roughly a 2 percent order cancel rate, and the real,
live run puts it at 49.4 percent over 180 days and 42.8 percent over 720
days, not close to the claimed figure. That result is reported plainly
in the article rather than quietly corrected in the README, consistent
with this repo's practice of checking a claim against real data before
repeating it.

Read the article: [`brokerTech.md`](brokerTech.md).
