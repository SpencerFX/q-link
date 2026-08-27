## About "openDash: Bridging a Browser to kdb+ Over Async IPC"

Unlike this repo's other articles, there's no `q` script to run here —
[`openDash`](https://github.com/SpencerFX/openDash1) is a separate
Node.js/React project (a gateway + dashboard) that sits in front of
[openQ](https://github.com/SpencerFX/openQ), the author's kdb+ platform.
This piece documents its design: correlating openQ gateway's
async, self-numbered replies over a pooled connection instead of one shared
socket; rebuilding every browser-supplied query as a validated q literal
rather than ever interpolating a client string; and fanning one shared
`.u.sub` feed out to many WebSocket clients with independent symbol filters.

One of its live dashboard pages — **Markout** — reads this repo's own
`analytics/markOutImpact.q` state straight off openQ's CEP, so the two
projects do share a real dependency: the analytics library lives here, the
live view of it lives there.

Read the article: [`openDash.md`](openDash.md).
