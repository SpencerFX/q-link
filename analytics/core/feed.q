//====================================================================
// Feed — connects to tp and drip-feeds a synthetic session (trades,
// rate ticks, orders, quotes) into it over real time, simulating a
// live market. Reuses the same synthetic generators the rest of the
// repo already relies on (data/generator.q, data/spreadGenerator.q) -
// this isn't a new data model, just a new way of delivering the same
// rows: one at a time, in timestamp order, spread out over real time
// instead of handed to a function as one large batch.
//
//   q analytics/core/feed.q
//====================================================================

system "l analytics/spread.q";       / .spreadSynth.genSession needs .spread.compose
system "l data/generator.q";
system "l data/spreadGenerator.q";

.feed.tpPort:5010;
.feed.tp:hopen .feed.tpPort;

//--------------------------------------------------------------------
// A modest synthetic session - small enough to drip-feed over about
// a minute of real wall-clock time for a live demo, not the 6h/30h
// sessions the perf/article scenarios use.
//--------------------------------------------------------------------
.feed.sym:`EURUSD;
.feed.start:.z.p;
.feed.dtSecs:0.5;
.feed.durationSecs:300;              / 5 synthetic minutes of rate ticks
.feed.base:.synth.genRateSeries[.feed.sym;.feed.start;.feed.durationSecs;.feed.dtSecs;1.1000;5e-8;2e-5];

.feed.spec:([] orderTime:.feed.start+`timespan$1e9*60*1+til 3; sym:3#.feed.sym;
  dirSign:1 -1 1f; tempBps:3.5 5.0 2.0f; permBps:1.0 2.5 0.2f; halfLifeSecs:8 15 5f);
.feed.orders:.synth.ordersFromSpec[.feed.spec;.feed.base];
.feed.rate:.synth.injectImpacts[.feed.base;.feed.spec];
.feed.trades:.synth.genTrades[.feed.sym;100;.feed.base;0.3];

.feed.spreadScenario:.spreadSynth.genSession[.feed.start;100;3];   / 200 quotes over ~10 min
.feed.quotes:delete totalSprd from .feed.spreadScenario`quotes;   / tp's `quotes` schema is the pre-compose wire shape - .spread.onQuote composes it itself on arrival

//--------------------------------------------------------------------
// Merge every stream into one time-sorted queue of (pubTime;table;idx)
// events, so publishing happens in genuine chronological order across
// trades/rate/orders/quotes rather than one stream at a time.
//--------------------------------------------------------------------
.feed.priv.mkEvents:{[t;tab;timeCol] ([] pubTime:tab timeCol; table:count[tab]#t; idx:til count tab)};
.feed.events:`pubTime xasc
  .feed.priv.mkEvents[`trades;.feed.trades;`tradeTime],
  .feed.priv.mkEvents[`rate;.feed.rate;`time],
  .feed.priv.mkEvents[`orders;.feed.orders;`orderTime],
  .feed.priv.mkEvents[`quotes;.feed.quotes;`time];

-1 "feed: ",(string count .feed.events)," events queued (",
  (string count .feed.trades)," trades, ",(string count .feed.rate)," rate, ",
  (string count .feed.orders)," orders, ",(string count .feed.quotes)," quotes)";

//@func | .feed.priv.row
//@desc  the single-row TABLE (not a dict - indexing by a 1-element
// list rather than a bare atom keeps the row/table shape TP expects)
// for event i.
.feed.priv.row:{[t;i]
  $[t=`trades; .feed.trades enlist i;
    t=`rate;   .feed.rate enlist i;
    t=`orders; .feed.orders enlist i;
    .feed.quotes enlist i]
 };

.feed.cursor:0;
.feed.batchSize:20;     / events published per timer tick
\t 200

//@func | .z.ts
//@desc  publish the next batch of queued events, in order, then a
// sync round-trip to flush them (an async send queued right before a
// process exits/idles can otherwise sit unflushed - see the README).
// Stops the timer once the queue is drained.
.z.ts:{[]
  n:count .feed.events;
  hi:n & .feed.cursor+.feed.batchSize;
  if[hi>.feed.cursor;
    batch:.feed.events .feed.cursor+til hi-.feed.cursor;
    {[tp;t;i] neg[tp](`upd;t;.feed.priv.row[t;i])}[.feed.tp;;] '[batch`table;batch`idx];
    .feed.tp "1+1";
   ];
  .feed.cursor:hi;
  if[.feed.cursor>=n; system"t 0"; -1 "feed: done, published ",(string n)," events"];
 };

//@func | .feed.status
//@desc  cursor position and completion state, for polling from another process.
.feed.status:{[] `published`total`done!(.feed.cursor;count .feed.events;.feed.cursor>=count .feed.events)};

-1 "feed: publishing to tp on port ",(string .feed.tpPort),", ",string[.feed.batchSize]," events/200ms";
