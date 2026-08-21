//====================================================================
// Performance check: every public function in analytics/markOutImpact.q
// and analytics/spread.q, timed against realistic synthetic data.
//
//   q perf/perfChk.q
//
// Methodology: each pure/batch function is timed via `system"ts do[n;expr]"`
// (kdb+'s built-in time+space profiler, called programmatically so the
// (ms;bytes) pair can be captured and tabulated rather than only printed)
// and averaged over n reps. Stateful "real-time path" functions
// (onTrade/onRate/onOrder/onBook/onQuote/sweepPending) are NOT safe to
// naively loop: onRate/onBook DRAIN their pending table on a match, so a
// second identical call measures an empty-hits no-op rather than the
// real cost. Those are benchmarked as a single realistic bulk call
// instead (seed N distinct pending rows, then time one tick that
// completes/evicts all of them at once) - see the "real-time" sections
// below for the seeding detail.
//====================================================================

system "l ./analytics/markOutImpact.q";
system "l ./data/generator.q";
system "l ./analytics/spread.q";
system "l ./data/spreadGenerator.q";

\c 60 240

//--------------------------------------------------------------------
// Benchmark harness
//--------------------------------------------------------------------
.perf.results:([] section:`$(); label:`$(); reps:`long$(); avgMs:`float$(); totalMs:`long$(); kb:`float$(); error:`$());

//@func | .perf.priv.run
//@desc  time `exprStr` (a q expression given as a string, referencing
// already-defined .perf.data.* globals) averaged over n reps via the
// built-in \ts profiler; n=1 runs exprStr as a single bare call
// (required for stateful/draining functions). Protected: a runtime
// error inside exprStr is caught and recorded as a failed row (nulls
// in the timing columns, message in `error`) rather than aborting the
// whole check.
.perf.priv.run:{[section;label;n;exprStr]
  full:$[n=1; exprStr; "do[",string[n],";(",exprStr,")]"];
  .perf.priv.errMsg:`;
  r:@[{system "ts ",x}; full; {.perf.priv.errMsg:`$x; 0N 0N}];
  ok:null .perf.priv.errMsg;
  `.perf.results insert (section;label;n;
    $[ok;r[0]%n;0n]; $[ok;r[0];0N]; $[ok;r[1]%1024f;0n]; .perf.priv.errMsg);
  };

//--------------------------------------------------------------------
// Benchmark data: markout/impact (analytics/markOutImpact.q)
//--------------------------------------------------------------------
/ 5x .synth.buildScenario[]'s sizes (it takes no size params, so this
/ rebuilds the same construction from the lower-level .synth.* pieces):
/ 30h session @ 0.5s ticks (~216,000 rate ticks), 10,000 trades, 25 orders
.perf.data.scaleFactor:5;
.perf.data.sym:`EURUSD;
.perf.data.start:.z.p - 0D06:00:00*.perf.data.scaleFactor;
.perf.data.dtSecs:0.5;
.perf.data.durSecs:.perf.data.scaleFactor*6*60*60;
.perf.data.nTrades:.perf.data.scaleFactor*2000;
.perf.data.nOrders:.perf.data.scaleFactor*5;
.perf.data.base:.synth.genRateSeries[.perf.data.sym;.perf.data.start;.perf.data.durSecs;.perf.data.dtSecs;1.1000;5e-8;2e-5];
.perf.data.orderTimes:.perf.data.start+`timespan$1e9*40*60*1+til .perf.data.nOrders;
.perf.data.spec:([] orderTime:.perf.data.orderTimes; sym:.perf.data.nOrders#.perf.data.sym;
  dirSign:.perf.data.nOrders#1 -1 1 -1 1f;
  tempBps:.perf.data.nOrders#3.5 5.0 2.0 6.5 4.0;
  permBps:.perf.data.nOrders#1.0 2.5 0.2 3.0 1.5;
  halfLifeSecs:.perf.data.nOrders#8 15 5 20 10f);
.perf.data.orders:.synth.ordersFromSpec[.perf.data.spec;.perf.data.base];
.perf.data.rate:.synth.injectImpacts[.perf.data.base;.perf.data.spec];
.perf.data.trades:.synth.genTrades[.perf.data.sym;.perf.data.nTrades;.perf.data.base;0.3];
.perf.data.book:.perf.data.rate;

.perf.data.deals:([] tradeID:.perf.data.trades`tradeID; sym:.perf.data.trades`sym;
  notional:1e6+9e6*(count .perf.data.trades)?1f);

.perf.data.markoutRows:.markout.calc[.perf.data.trades;.perf.data.rate];
.perf.data.calcRes:.impact.calc[.perf.data.orders;.perf.data.book];

.perf.data.constTradeGetter:{[d] .perf.data.trades};
.perf.data.constRateGetter:{[d] .perf.data.rate};
.perf.data.dates:2024.01.01+til 4;

//--------------------------------------------------------------------
// Benchmark data: spread (analytics/spread.q)
//--------------------------------------------------------------------
.perf.data.spread:.spreadSynth.genSession[.z.p-0D02:00:00;15000;1.5];   / 30,000 quotes (5x)
.perf.data.quotes:.perf.data.spread`quotes;
.perf.data.benchmark:.perf.data.spread`benchmark;

//====================================================================
// .util.*
//====================================================================
.perf.priv.run[`util;`buildGrid;2000;"(.util.buildGrid (0.1*1+til 10),(2+til 14),30 60 120 180 300 600f)"];
.perf.priv.run[`util;`toTimespan;2000;"(.util.toTimespan .markout.gridSecs)"];
.perf.priv.run[`util;`explode;50;"(.util.explode[.perf.data.trades;`tradeTime;.markout.gridNS])"];

//====================================================================
// .markout.* — batch
//====================================================================
.perf.priv.run[`markout.batch;`calc;20;"(.markout.calc[.perf.data.trades;.perf.data.rate])"];
.perf.priv.run[`markout.batch;`calcDate;20;"(.markout.calcDate[.perf.data.dates 0;.perf.data.constTradeGetter;.perf.data.constRateGetter])"];
.perf.priv.run[`markout.batch;`calcAll;5;"(.markout.calcAll[.perf.data.dates;.perf.data.constTradeGetter;.perf.data.constRateGetter])"];
.perf.priv.run[`markout.batch;`notionalWeighted;50;"(.markout.notionalWeighted[.perf.data.markoutRows;.perf.data.deals])"];

//====================================================================
// .markout.* — real-time path
//====================================================================
.markout.pending:0#.markout.pending; .markout.completed:0#.markout.completed;

/ onTrade: same tradeID reused every rep -> upsert overwrites the same
/ 61 keys each time, pending table stays bounded, safe to loop
.perf.data.tr0:`tradeID`tradeTime`tradeRate`sym!(999999;.perf.data.trades[`tradeTime][0];1.1;`EURUSD);
.perf.priv.run[`markout.rt;`onTrade;500;"(.markout.onTrade .perf.data.tr0)"];
.markout.pending:0#.markout.pending;

/ onRate: seed 500 DISTINCT trades (so pending has 500*61 rows across many
/ tradeIDs), then a single tick whose time is past every offset for
/ `EURUSD -> one call drains/completes all of them at once
{.markout.onTrade `tradeID`tradeTime`tradeRate`sym!(100000+x;.perf.data.trades[`tradeTime][x];1.1;`EURUSD)} each til 500;
.perf.data.rt0:`sym`time`mid!(`EURUSD;.perf.data.rate[`time][count[.perf.data.rate]-1];1.10001);
.perf.priv.run[`markout.rt;`onRate_bulkDrain500;1;"(.markout.onRate .perf.data.rt0)"];
.markout.pending:0#.markout.pending; .markout.completed:0#.markout.completed;

/ sweepPending: reseed the same 500-trade pending set, then evict all of
/ it in one call (now set far beyond pendingTTL for every row)
{.markout.onTrade `tradeID`tradeTime`tradeRate`sym!(200000+x;.perf.data.trades[`tradeTime][x];1.1;`EURUSD)} each til 500;
.perf.data.farFuture:.z.p+1D;
.perf.priv.run[`markout.rt;`sweepPending_evict500;1;"(.markout.sweepPending .perf.data.farFuture)"];
.markout.pending:0#.markout.pending;

//====================================================================
// .impact.* — batch
//====================================================================
.perf.priv.run[`impact.batch;`calc;100;"(.impact.calc[.perf.data.orders;.perf.data.book])"];
.perf.priv.run[`impact.batch;`decompose;200;"(.impact.decompose[.perf.data.calcRes;10;30])"];
.perf.priv.run[`impact.batch;`bySymSide;200;"(.impact.bySymSide[.perf.data.calcRes;.perf.data.orders])"];

//====================================================================
// .impact.* — real-time path
//====================================================================
.impact.pending:0#.impact.pending; .impact.completed:0#.impact.completed;

.perf.data.ord0:`orderID`orderTime`orderRate`sym`side!(999999;.perf.data.book[`time][0];1.1;`EURUSD;`buy);
.perf.priv.run[`impact.rt;`onOrder;500;"(.impact.onOrder .perf.data.ord0)"];
.impact.pending:0#.impact.pending;

{.impact.onOrder `orderID`orderTime`orderRate`sym`side!(100000+x;.perf.data.book[`time][x];1.1;`EURUSD;`buy)} each til 500;
.perf.data.bk0:`sym`time`mid!(`EURUSD;.perf.data.book[`time][count[.perf.data.book]-1];1.10001);
.perf.priv.run[`impact.rt;`onBook_bulkDrain500;1;"(.impact.onBook .perf.data.bk0)"];
.impact.pending:0#.impact.pending; .impact.completed:0#.impact.completed;

{.impact.onOrder `orderID`orderTime`orderRate`sym`side!(200000+x;.perf.data.book[`time][x];1.1;`EURUSD;`buy)} each til 500;
.perf.priv.run[`impact.rt;`sweepPending_evict500;1;"(.impact.sweepPending .perf.data.farFuture)"];
.impact.pending:0#.impact.pending;

//====================================================================
// .spread.* — compose / decompose / waterfall
//====================================================================
.perf.priv.run[`spread.compose;`compose;100;"(.spread.compose .perf.data.quotes)"];
.perf.priv.run[`spread.compose;`decompose;50;"(.spread.decompose .perf.data.quotes)"];
.perf.priv.run[`spread.compose;`waterfall;50;"(.spread.waterfall .perf.data.quotes)"];

//====================================================================
// .spread.* — aggregation
//====================================================================
.perf.priv.run[`spread.agg;`priv.wavgAggCols;2000;"(.spread.priv.wavgAggCols .spread.componentCols)"];
.perf.priv.run[`spread.agg;`wavgBy;100;"(.spread.wavgBy[.perf.data.quotes;enlist`sym])"];
.perf.priv.run[`spread.agg;`util.timeBucket;2000;"(.spread.util.timeBucket[`minute;`time])"];
.perf.priv.run[`spread.agg;`byTime;50;"(.spread.byTime[.perf.data.quotes;`minute;`$()])"];
.perf.priv.run[`spread.agg;`byRegime;100;"(.spread.byRegime[.perf.data.quotes;`$()])"];

//====================================================================
// .spread.* — reconciliation
//====================================================================
.perf.priv.run[`spread.recon;`vsReference;50;"(.spread.vsReference[.perf.data.quotes;.perf.data.benchmark;`time`sym;`benchmarkSprd])"];

//====================================================================
// .spread.* — real-time path
//====================================================================
.perf.data.q0:first .perf.data.quotes;
.perf.priv.run[`spread.rt;`onQuote;1000;"(.spread.onQuote .perf.data.q0)"];
.perf.priv.run[`spread.rt;`latest;1000;"(.spread.latest[])"];

//====================================================================
// Report
//====================================================================
-1 "";
-1 "Dataset sizes: markout/impact rate=",(string count .perf.data.rate),
  " trades=",(string count .perf.data.trades),
  " orders=",(string count .perf.data.orders),
  " | spread quotes=",(string count .perf.data.quotes),
  " benchmark=",string count .perf.data.benchmark;
-1 "";
show .perf.results;
-1 "";
-1 "Note: .markout.calcAll uses peach — in this single-process (no -s N)";
-1 "session peach degrades to sequential each, so calcAll's number here";
-1 "reflects sequential cost, not parallel speedup.";
exit 0
