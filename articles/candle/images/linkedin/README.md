# LinkedIn-ready code/table images

One PNG per code block and table in [`candle.md`](../../candle.md), numbered
in reading order. Same convention as every other article's `images/linkedin/`
set in this repo: dark syntax-highlighted cards for code, light cards for
tables, auto-cropped tight to content.

| # | File | Where it goes |
|---|---|---|
| 01 | `01_meta.png` | 32 patterns, one shared shape — `.candle.meta` |
| 02 | `02_priortrend.png` | The shape isn't the signal — `.candle.priorTrend` |
| 03 | `03_hammer-hangingman.png` | The shape isn't the signal — hammer vs hangingMan, side by side |
| 04 | `04_where-bug.png` | Porting to a q build that fights you — the where-clause bug |
| 05 | `05_nested-lambda-bug.png` | Porting to a q build that fights you — the nested-lambda bug |
| 06 | `06_maxmin-bug.png` | Porting to a q build that fights you — dyadic max/min |
| 07 | `07_verify-query.png` | Verifying against a real crash — the live query |
| 08 | `08_verify-table.png` | Verifying against a real crash — hammer + morning star fires |
| 09 | `09_kicking-code.png` | kicking without a gap — the function itself |
| 10 | `10_kicking-check.png` | kicking without a gap — the real 42/87 split |
| 11 | `11_freq-table.png` | How often does a pattern actually fire — top/bottom of the real table |
| 12 | `12_crash-compare.png` | Six stocks, one crash — every pattern near each stock's real low |
| 13 | `13_kicking-multistock.png` | kicking without a gap — the real-gap rate across six names |
| 14 | `14_edgetest-code.png` | Forward-return edge test — the forward-return formula and edge-stat query |
| 15 | `15_edgetest-table.png` | Forward-return edge test — top results by \|t-stat\|, 105 pattern×side×horizon combos |
| 16 | `16_bt-alpha.png` | Wired into backtest as one alpha among four — `.bt.alphas.candlePattern` |

## Regenerating

Built by a small headless-Chromium renderer (msedge `--headless
--screenshot`) over hand-highlighted q source, plus a Python autocrop
pass — not checked into the repo. Ask to regenerate this set if
`candle.md`'s code blocks or tables change.
