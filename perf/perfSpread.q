//====================================================================
// Performance report: analytics/spread.q — .spread.* — timed against
// realistic synthetic data.
//
//   q perf/perfSpread.q
//
// See perf/perfChk.q for the shared timing harness and methodology.
//====================================================================

system "l ./analytics/spread.q";
system "l ./data/spreadGenerator.q";
system "l ./perf/perfChk.q";

//--------------------------------------------------------------------
// Benchmark data
//--------------------------------------------------------------------
.perf.data.spread:.spreadSynth.genSession[.z.p-0D02:00:00;15000;1.5];   / 30,000 quotes (5x)
.perf.data.quotes:.perf.data.spread`quotes;
.perf.data.benchmark:.perf.data.spread`benchmark;

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
-1 "Dataset sizes: quotes=",(string count .perf.data.quotes),
  " benchmark=",string count .perf.data.benchmark;
-1 "";
.perf.report[];
exit 0
