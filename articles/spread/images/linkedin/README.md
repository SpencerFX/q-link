# LinkedIn-ready code/table images

One PNG per code block and table in [`spreadAnalytics.md`](../../spreadAnalytics.md),
numbered in reading order, so they can be pasted into a LinkedIn article in place of
the original markdown — LinkedIn's editor doesn't preserve code formatting or tables,
so these carry their own styling instead of relying on the platform's text formatting.

Regenerate with the script at the bottom of this file if the article's code/tables
change — filenames and numbering are stable as long as block order doesn't change.

| # | File | Where it goes |
|---|---|---|
| 01 | `01_run-initSpread.png` | Repo — interactive load command |
| 02 | `02_run-testSpread.png` | Repo — test-suite run command |
| 03 | `03_componentCols-compose.png` | The component model — `componentCols` + `compose` |
| 04 | `04_meta-quotes.png` | The component model — `q)meta scenario\`quotes` |
| 05 | `05_wavgAggCols-wavgBy.png` | One weighting rule, three entry points — `wavgAggCols` + `wavgBy` |
| 06 | `06_spreadGenerator-injection.png` | On data — injected stress/benchmark snippet |
| 07 | `07_recovery-output.png` | Interpreting the results — `q)recovery` |
| 08 | `08_byRegime-output.png` | Interpreting the results — aggression comparison |
| 09 | `09_shareByTime.png` | One more composition — `shareByTime` |
| 10 | `10_wpctl.png` | The mean can hide the tail — `priv.wpctl` |
| 11 | `11_pctlByTime.png` | The mean can hide the tail — `pctlByTime` |
| 12 | `12_vsReference.png` | Reconciliation vs. an outside reference — `vsReference` |
| 13 | `13_run-perf.png` | Appendix: performance — perf runner commands |
| 14 | `14_component-table.png` | The component model — component reference table |
| 15 | `15_perf-table.png` | Appendix: performance — results table |

## Style

- **Code blocks**: dark card (`#1a2733`), syntax-highlighted — namespaces/functions
  (`.spread.*`, `.util.*`) in blue, keywords (`select`/`update`/`from`/`by`/…) in
  orange, symbols (`` `sym ``) in aqua-green, numbers in violet, comments muted
  italic. Console-output blocks (`q)...`) and shell-invocation blocks (`q path.q`)
  get a plain monospace render instead, with just the prompt highlighted, since
  they're output/commands rather than source.
- **Tables**: light card (`#fcfcfb`) matching the article's own table styling, with
  a shaded header row and code-styled cells for identifier columns.
- Both use the same hues as [`../header.png`](../header.png) so everything in the
  article/post shares one visual identity, and are auto-cropped tight to content —
  no fixed canvas size, no dead space, safe to drop straight into a LinkedIn image
  block at native resolution.

## Regenerating

Built by a small headless-Chromium renderer (msedge `--headless --screenshot`), not
checked into the repo (it lives in the article-writing scratch space). Ask to
regenerate this set if `spreadAnalytics.md`'s code blocks or tables change.
