//====================================================================
// CEP — subscribes to the tickerplant and drives the real-time
// markout/impact/spread calculations as ticks arrive.
//
//   q analytics/core/cep.q             (listens on 5013, tp on 5010)
//   q analytics/core/cep.q -p 5014     (override cep's own port)
//
// This is deliberately thin: analytics/markOutImpact.q and analytics/
// spread.q already have a complete, tested real-time path
// (.markout.onTrade/.onRate/.sweepPending, .impact.onOrder/.onBook/
// .sweepPending, .spread.onQuote) - cep's whole job is routing each
// incoming table's rows to the right one of those, on a live feed
// instead of a synthetic batch.
//====================================================================
\p 5013

system "l analytics/markOutImpact.q";
system "l analytics/spread.q";

.cep.tpPort:5010;
.cep.tp:hopen .cep.tpPort;
.cep.tp(`.tp.sub;`);  / subscribe to every table tp has; cep needs the ticks, not tp's schemas

//@func | upd
//@param | t | -11 | table name
//@param | data | 99 | unkeyed table of new rows, columns matching t's schema on tp
//@desc
// route each new row to the matching real-time registration
// function(s). `rate` feeds BOTH .markout's rate-tick path and
// .impact's book-tick path - the batch functions already treat one
// mid-price series as both a trade's post-fill rate and an order's
// post-arrival book, and the real-time path keeps that symmetry.
//@desc
upd:{[t;data]
  $[t=`trades; .markout.onTrade each data;
    t=`rate;   (.markout.onRate each data; .impact.onBook each data);
    t=`orders; .impact.onOrder each data;
    t=`quotes; .spread.onQuote each data;
    -2 "cep: unrecognized table ",string t]
 };

//--------------------------------------------------------------------
// Periodic sweep - evict pending offsets a dead symbol or a gap in
// the feed left stranded, same TTL-based cleanup markOutImpact.q's
// own doc comments describe for the batch/demo path.
//--------------------------------------------------------------------
.z.ts:{[]
  .markout.sweepPending .z.p;
  .impact.sweepPending .z.p;
 };
\t 5000

//@func | .cep.status
//@desc  row counts across every real-time analytics table, for a
// quick sanity check of what cep has processed/is still waiting on.
.cep.status:{[]
  `markoutPending`markoutCompleted`impactPending`impactCompleted`spreadSnap!
   (count .markout.pending; count .markout.completed; count .impact.pending; count .impact.completed; count .spread.snap)
 };

-1 "cep: subscribed, sweeping pending every 5s, listening on port ",string system"p";
