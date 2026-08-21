//====================================================================
// Tickerplant — schemas, publish/subscribe, append-only log.
//
//   q analytics/core/tp.q            (listens on 5010)
//   q analytics/core/tp.q -p 5011    (override the port)
//
// Written from scratch against a self-contained protocol (not Kx's
// tick.q/sym.q, which this repo doesn't assume are present): a
// subscriber connects and calls `.tp.sub[tabs]` over SYNC ipc, which
// registers its handle and hands back the empty schema for each table
// it asked for; the feed then calls `upd[t;data]` over ASYNC ipc for
// every new row/batch, which this process appends to today's log file
// and republishes to every current subscriber of that table.
//
// `data` for `upd` is always an unkeyed table (one row minimum) whose
// columns match the table's schema below - single-row dicts are the
// analytics functions' shape (.markout.onTrade etc.), not the wire
// shape; feed.q sends `enlist` around a single-row dict to get there.
//====================================================================
\p 5010

//--------------------------------------------------------------------
// Schemas - one per upstream table. `rate` is deliberately shared
// between .markout (rate ticks) and .impact (book ticks): both just
// want a stream of (time;sym;mid), and that's exactly what a market
// data tick is.
//--------------------------------------------------------------------
trades:([] tradeID:`long$(); tradeTime:`timestamp$(); tradeRate:`float$(); sym:`symbol$());
rate:([] time:`timestamp$(); sym:`symbol$(); mid:`float$());
orders:([] orderID:`long$(); orderTime:`timestamp$(); orderRate:`float$(); sym:`symbol$(); side:`symbol$());
quotes:([] time:`timestamp$(); sym:`symbol$(); aggression:`symbol$(); marketStatus:`symbol$(); weight:`float$();
  refSprd:`float$(); baseSprd:`float$(); clientSprd:`float$(); volSprd:`float$(); smoothSprd:`float$(); fallbackSprd:`float$(); alphaSprd:`float$());

.tp.schemas:`trades`rate`orders`quotes;

//--------------------------------------------------------------------
// Subscriptions
//--------------------------------------------------------------------
.tp.subs:.tp.schemas!count[.tp.schemas]#enlist `int$();

//@func | .tp.sub
//@param | tabs | 11 | table names to subscribe to, symbol list (or generic null `` ` `` for all)
//@desc
// called over SYNC ipc by a subscriber (rdb.q/cep.q). Registers the
// caller's handle against each requested table and returns the empty
// schema for each, so the caller can build matching local structures
// before any ticks arrive.
//@desc
.tp.sub:{[tabs]
  tabs:$[tabs~`;.tp.schemas;tabs];
  .tp.subs[tabs]:{distinct x,y}[;.z.w] each .tp.subs tabs;
  tabs!{0#value x} each tabs
 };

//@func | .tp.priv.dropHandle
//@desc  remove a (now-dead) handle from every table's subscriber list -
// called from .z.pc when a subscriber disconnects.
.tp.priv.dropHandle:{[h] .tp.subs:(key .tp.subs)!{x except y}[;h] each value .tp.subs};
.z.pc:{[h] .tp.priv.dropHandle h};

//--------------------------------------------------------------------
// Logging - append-only, one file per calendar day. Durability/audit
// trail: every upd this process ever republished is recoverable from
// disk. (Replay-on-startup for rdb/cep is a natural next step this
// doesn't wire up - see the README.)
//--------------------------------------------------------------------
.tp.logFile:`$":analytics/core/tplog/",(string .z.D),".tplog";
.tp.logHandle:hopen .tp.logFile;

.tp.priv.logWrite:{[t;data] .tp.logHandle enlist (`upd;t;data)};

//@func | .tp.priv.sendOne
//@desc  async-send `msg` to a single subscriber handle, dropping it on
// failure. Written as a top-level function taking (h;msg) rather than
// an inline closure: projecting `dropHandle`'s ONE-arg lambda with its
// only arg already supplied evaluates it immediately (not a deferred
// call), which would drop every subscriber the instant a publish is
// attempted, success or not - passing this 2-arg function's error slot
// as `f[h;]` (arg 2 left open) is what makes it a genuine projection
// `@` can invoke later, only if the send actually fails.
.tp.priv.sendOne:{[h;msg] @[neg h;msg;{[h;err] .tp.priv.dropHandle h}[h;]]};

//--------------------------------------------------------------------
// upd - called (async) by the feed for every new row/batch
//--------------------------------------------------------------------
//@func | upd
//@param | t | -11 | table name
//@param | data | 99 | unkeyed table of new rows, columns matching t's schema
//@desc
// log the update, then republish it (async) to every current
// subscriber of `t`. A subscriber that's died since it last
// subscribed is dropped rather than retried.
//@desc
upd:{[t;data]
  .tp.priv.logWrite[t;data];
  .tp.priv.sendOne[;(`upd;t;data)] each .tp.subs t;
 };

-1 "tp: listening on port ",string system"p";
-1 "tp: logging to ",string .tp.logFile;
