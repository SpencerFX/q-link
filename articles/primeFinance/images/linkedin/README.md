# LinkedIn-ready code/table images

One PNG per code block and table in [`primeFinance.md`](../../primeFinance.md),
numbered in reading order, so they can be pasted into a LinkedIn article in place of
the original markdown — LinkedIn's editor doesn't preserve code formatting or tables,
so these carry their own styling instead of relying on the platform's text formatting.

Regenerate with the script noted below if the article's code/tables change —
filenames and numbering are stable as long as block order doesn't change.

| # | File | Where it goes |
|---|---|---|
| 01 | `01_htbScore.png` | Ranking, not summing — `.prime.htbScore` |
| 02 | `02_allocate-loop.png` | Ranking, not summing — `.prime.allocate`'s per-lender cap loop |
| 03 | `03_reservation-write.png` | Ranking, not summing — one reservation row per lender line |
| 04 | `04_aapl-alloc.png` | Ranking, not summing — live AAPL locate result |
| 05 | `05_gme-alloc.png` | Ranking, not summing — live GME locate result (thin book) |
| 06 | `06_positionCoverage.png` | What actually came up short — `.prime.positionCoverage` |
| 07 | `07_coverage-table.png` | What actually came up short — live coverage table |
| 08 | `08_applyRecall.png` | A recall's job is to notify, not to undo — `.prime.applyRecall` |
| 09 | `09_buyin-sweep.png` | Buy-ins and the sweep — `.prime.raiseBuyin` + `.prime.sweep` |
| 10 | `10_buyin-dup-finding.png` | Buy-ins and the sweep — live duplicate-alert finding |
| 11 | `11_lenders-schema.png` | Reference data that arrives out of order — `.prime.lenders` schema |
| 12 | `12_expo-lj.png` | Reference data that arrives out of order — `.prime.expo.build`'s `lj` |
| 13 | `13_expectedFeeBp.png` | Risk marked to something real — `.prime.calib.expectedFeeBp` |
| 14 | `14_pnl-table.png` | Risk marked to something real — live NVDA position-risk table |
| 15 | `15_crowd-build.png` | How crowded is a name, really — `.prime.crowd.bucket` + `.prime.crowd.build` |
| 16 | `16_crowding-table.png` | How crowded is a name, really — live crowding table |
| 17 | `17_perf-table.png` | Appendix: performance — live `\ts` results table |

## Style

- **Code blocks**: dark card (`#1a2733`), syntax-highlighted — namespaces/functions
  (`.prime.*`, `.util.*`) in blue, keywords (`select`/`update`/`from`/`by`/…) in
  orange, symbols (`` `sym ``) in aqua-green, numbers in violet, comments muted
  italic.
- **Tables**: light card (`#fcfcfb`) matching the article's own table styling, with
  a shaded header row and status-colored pill tags for bucket/flag columns
  (`FULL`/`CHEAP`/`LOW` = green, `PARTIAL`/`MODERATE` = amber, `AT_RISK`/`RICH` =
  orange, `UNLOCATED`/`EXTREME` = red, `FAIR` = gray).
- Both use the same hues as [`../header.png`](../header.png) so everything in the
  article/post shares one visual identity, and are auto-cropped tight to content —
  no fixed canvas size, no dead space, safe to drop straight into a LinkedIn image
  block at native resolution.

## Regenerating

Built by a small headless-Chromium renderer (msedge `--headless --screenshot`) over
hand-highlighted q source (regex-tokenized, not a general lexer) plus a Python
autocrop pass, not checked into the repo (it lives in the article-writing scratch
space). Ask to regenerate this set if `primeFinance.md`'s code blocks or tables
change.
