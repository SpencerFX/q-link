# LinkedIn-ready code/table images

One PNG per code block and table in [`openQ.md`](../../openQ.md), numbered
in reading order, so they can be pasted into a LinkedIn article in place
of the original markdown — LinkedIn's editor doesn't preserve code
formatting or tables, so these carry their own styling instead of relying
on the platform's text formatting. The four architecture diagrams
(`../topology.png`, `../module-plugin.png`, `../active-standby.png`,
`../gateway.png`) aren't part of this numbered set — they're full-width
figures embedded directly in the article, not per-block social crops.

| # | File | Where it goes |
|---|---|---|
| 01 | `01_roles-table.png` | The six steady-state roles — reference table |
| 02 | `02_init-dispatch.png` | One bootstrap script, one dispatch table — `init.q`'s `-procType` dispatch |
| 03 | `03_cfg-merge.png` | One bootstrap script, one dispatch table — `.oq.cfg.merge` |
| 04 | `04_cep-json.png` | A module is six JSON files — `primefinance/cep.json` |
| 05 | `05_startup-order.png` | A module is six JSON files — `startupAllByModule.sh`'s role order |
| 06 | `06_whichActive.png` | Two processes pretending to be one — `.oq.idb.whichActive` |
| 07 | `07_pub-fix.png` | Two processes pretending to be one — `.u.pub`'s per-handle protected send |
| 08 | `08_unsub-sync.png` | Two processes pretending to be one — `.u.unsub` called synchronously |
| 09 | `09_pivot-steps.png` | idb doesn't subscribe to anything — the pivot-and-harvest cycle |
| 10 | `10_save-publish.png` | idb doesn't subscribe to anything — `.oq.save.publish`, table-by-table |
| 11 | `11_hdb-chk.png` | idb doesn't subscribe to anything — `.Q.chk` + unconditional reload |
| 12 | `12_chooseServers.png` | One query, many backends, one reply — `.oq.gw.chooseServers` |
| 13 | `13_checkResults.png` | One query, many backends, one reply — `.util.gw.checkResults` |
| 14 | `14_replayMissedTicks.png` | CEPs chain, and they remember what they missed — `.oq.cep.replayMissedTicks` |
| 15 | `15_report-usage.png` | CEPs chain, and they remember what they missed — bringing up `report` |

## Style

Same convention as [`../../primeFinance/images/linkedin/`](../../primeFinance/images/linkedin/)
and [`../../spread/images/linkedin/`](../../spread/images/linkedin/):
dark syntax-highlighted cards (`#1a2733`) for code (namespaces/functions
in blue, keywords in orange, symbols in aqua-green, numbers in violet,
comments muted italic; JSON keys reuse the namespace blue, string values
amber, numeric values violet), light cards (`#fcfcfb`) for tables,
auto-cropped tight to content.

## Regenerating

Built by a small headless-Chromium renderer (msedge `--headless
--screenshot`) over hand-highlighted q/JSON/bash source, plus a Python
autocrop pass — not checked into the repo (lives in the article-writing
scratch space). Ask to regenerate this set if `openQ.md`'s code blocks or
tables change.
