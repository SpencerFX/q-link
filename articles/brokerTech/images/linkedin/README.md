# LinkedIn-ready code/result images

One PNG per code block and captured result in [`brokerTech.md`](../../brokerTech.md),
numbered in reading order. Same convention as every other article's
`images/linkedin/` set in this repo: dark syntax-highlighted cards for
real code (q or JavaScript), plain dark cards (no syntax coloring, since
it isn't code) for captured "live result" output, auto-cropped tight to
content.

| # | File | Where it goes |
|---|---|---|
| 01 | `01_executed-orders.png` | The data and its sign conventions - `.brk.executed` / `.brk.orders` |
| 02 | `02_concentration-result.png` | Exposure and concentration - real book concentration snapshot |
| 03 | `03_peakconcurrent.png` | Exposure and concentration - `.brk.expo.peakConcurrent`, the sweep line |
| 04 | `04_stopslippage.png` | Execution quality - `.brk.exec.stopSlippage` |
| 05 | `05_cancelrate-broker.png` | Execution quality - real cancel rate by broker (the README claim check) |
| 06 | `06_toxscore-doc.png` | Toxicity scoring - `.brk.tox.score`'s five components |
| 07 | `07_tox-buckets-result.png` | Toxicity scoring - real bucket counts |
| 08 | `08_book-recommend-doc.png` | A book, B book, and the routing call - `.brk.book.recommend` |
| 09 | `09_routing-optimise-result.png` | A book, B book, and the routing call - real optimisation headline |
| 10 | `10_cluster-result.png` | Client clustering - real k=5 cluster table |
| 11 | `11_alert-breaches-doc.png` | Revenue attribution and risk alerts - `.brk.alert.breaches` |
| 12 | `12_gateway-suite.png` | The openDash layer - gateway query echoing `.brk.cfg` |
| 13 | `13_absimroute.png` | The openDash layer - `abSimRoute`, the A/B Book simulator |
| 14 | `14_txsimscore.png` | The openDash layer - `txSimScore`, the Toxic Analysis simulator |

## Regenerating

Built by a small headless-Chromium renderer (msedge `--headless
--screenshot`) over hand-highlighted q/JS source, plus a Python autocrop
pass - not checked into the repo. Ask to regenerate this set if
`brokerTech.md`'s content changes.
