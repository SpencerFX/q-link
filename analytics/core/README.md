# Real-time core: tp → rdb / cep

A from-scratch tickerplant/rdb/cep topology that runs `analytics/markOutImpact.q` and
`analytics/spread.q` on a live tick stream instead of a batch. Written against a
self-contained protocol — this doesn't assume Kx's `tick.q`/`sym.q` are present, just
plain IPC.

```
        ┌────────┐   async upd    ┌────────┐
        │  feed  │ ─────────────► │   tp   │
        └────────┘   (port 5010)  └───┬────┘
                                       │ republish (async)
                          ┌────────────┴────────────┐
                          ▼                          ▼
                    ┌──────────┐               ┌──────────┐
                    │   rdb    │               │   cep    │
                    │ (5011)   │               │ (5013)   │
                    │ in-memory│               │.markout.*│
                    │  mirror  │               │.impact.* │
                    └──────────┘               │.spread.* │
                                                └──────────┘
```

- **`tp.q`** — the tickerplant. Defines the four wire schemas, logs every update to an
  append-only daily file, and republishes to subscribers.
- **`rdb.q`** — subscribes to every table, keeps today's ticks in memory, can splay to
  an end-of-day HDB.
- **`cep.q`** — subscribes to every table and routes each row into the same
  `.markout.on*`/`.impact.on*`/`.spread.onQuote` real-time functions the rest of the
  repo already has; this is where the live markout/impact/spread numbers come from.
- **`feed.q`** — a client, not a server. Builds a synthetic session with
  `data/generator.q`/`data/spreadGenerator.q` and drip-feeds it into `tp` over real
  wall-clock time (a 200ms timer, 20 events/tick) to simulate a live market.

## Running it

Four separate `q` processes, from the repo root, in this order:

```bash
q analytics/core/tp.q       # listens on 5010
q analytics/core/rdb.q      # listens on 5011, connects to tp on 5010
q analytics/core/cep.q      # listens on 5013, connects to tp on 5010
q analytics/core/feed.q     # no listening port — connects to tp and starts publishing
```

Each of `rdb.q`/`cep.q` takes tp's port as `.rdb.tpPort`/`.cep.tpPort` if you need to
point at a non-default tickerplant. Poll progress from any other q session:

```q
q)h:hopen 5011; h "value .rdb.status[]"   / row counts per table
q)h:hopen 5013; h "value .cep.status[]"   / markout/impact pending+completed, spread snap count
q)h:hopen 5010; h "value .feed.status[]"  / feed's own cursor (from the feed process itself, if queried before it exits)
```

## Protocol

- **Subscribe** — `tp(`.tp.sub;tabs)` over **sync** IPC. `tabs` is a symbol list of
  table names, or generic null `` ` `` for all. Returns a dict of the empty schema for
  each table, so a subscriber can build matching local structures before any ticks
  arrive — subscribers never hardcode tp's schemas.
- **Publish** — `neg[tp](`upd;t;data)` over **async** IPC. `data` is always an
  unkeyed table (≥1 row) whose columns match that table's schema on tp, not a bare
  dict — `feed.q`'s `.feed.priv.row` builds a real 1-row table via `enlist`-indexing
  for exactly this reason.
- **Wire schemas** (`tp.q`): `trades` (tradeID, tradeTime, tradeRate, sym), `rate`
  (time, sym, mid — shared by both `.markout`'s rate ticks and `.impact`'s book
  ticks), `orders` (orderID, orderTime, orderRate, sym, side), `quotes` (time, sym,
  aggression, marketStatus, weight, + the seven `.spread.componentCols` —
  **pre-`.spread.compose`**, no `totalSprd`; `.spread.onQuote` composes it itself on
  arrival).

## Layout

```
analytics/core/tp.q      tickerplant — schemas, pub/sub, append-only log
analytics/core/rdb.q     realtime DB — in-memory mirror + EOD splay
analytics/core/cep.q     complex event processor — real-time markout/impact/spread
analytics/core/feed.q    synthetic session, drip-fed into tp over real time
analytics/core/tplog/    tp's daily append-only log (<date>.tplog)
analytics/core/hdb/      rdb.eod's splay output (<date>/<table>/)
```

## Known limitations

- **No replay-on-startup.** tp's log is a durable audit trail, but rdb/cep don't
  replay it when they (re)connect — a subscriber that starts mid-session only sees
  ticks from the moment it subscribes onward. Wiring up `-11!` replay against
  `.tp.logFile` on `rdb`/`cep` startup is the natural next step.
- **No `.z.pc` handling on rdb/cep.** If tp restarts, subscribers don't currently
  reconnect/resubscribe automatically.

## Gotchas hit building this

Left here because they're easy to reintroduce:

- **A backslash system-command can't appear inside an expression.** `\t 0` inside an
  `if[]` or a function body is a parse error — use the callable form, `system"t 0"`.
- **A backslash command consumes the rest of its line as a literal argument,
  including trailing comments.** `` \t 200 / tick every 200ms `` feeds `\t` the
  string `"200 / tick every 200ms"`, not the number 200 — it fails to parse and the
  timer silently stays off. Put comments on their own line, never after a backslash
  command.
- **An unbracketed verb swallows everything to its right before an earlier comma
  binds.** ``string n," events"`` parses as `` string[n," events"] `` (q evaluates
  right-to-left with no operator precedence), not `` (string n)," events" `` —
  `string` gets applied to the *joined* `` (n;" events") `` pair first, producing a
  nested list instead of a flat string, which then blows up wherever it's printed or
  sent. Parenthesize `string`/`` `$ ``/similar calls whenever more comma-joins follow
  them on the same line.
- **Async sends queued right before a process exits/idles can be silently dropped.**
  The OS may never flush the TCP buffer. Follow the last `neg[h](...)` in a batch
  with a synchronous round-trip on the same handle (`h "1+1"`) before the process
  moves on or closes the connection — `tp.q`'s republish and `feed.q`'s per-tick
  batch both do this.
- **A fully-saturated 1-arg lambda application evaluates immediately, not lazily.**
  `{[h] f h}[h]` runs the instant it's *constructed*, not deferred until called — this
  broke tp's original async-send error handler (it dropped every subscriber on every
  send, success or not). Use a genuine open-slot projection instead:
  `f[h;]` (trailing `;` leaves arg 2 open for `@[...]` to fill in only on failure).
- **Bracket/`#` access on a keyed table means "look up this key," not "get this
  column."** Applies throughout `.spread.*`, not just here.
- **`` ` sv `` path-join requires every element to already be a symbol.** Mixing a
  symbol with a plain string in the list silently produces a wrong/concatenated path
  — cast every component first: `` `$(string d;string t) ``.
