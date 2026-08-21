//====================================================================
// Standalone functions: FX Spread Build-Up & Attribution
//
// General-purpose kdb+/q implementation of a pricing engine's quoted
// spread as a sum of named, explainable components:
//   .spread.*   - compose a total spread from its components, break
//                 a total back down into each component's
//                 contribution, aggregate that build-up by arbitrary
//                 keys/time buckets, reconcile it against an external
//                 reference/realized spread, and track it in real
//                 time as new quotes arrive.
//
// The same shape generalizes any "total = sum of named adjustments"
// pricing model - only .spread.componentCols needs to change.
//====================================================================

//--------------------------------------------------------------------
// Component schema
//--------------------------------------------------------------------
// A quoted spread is modelled as the sum of seven named components:
//   refSprd       reference/baseline spread before any adjustment
//   baseSprd      core pricing-engine markup
//   clientSprd    client-tier/relationship skew (wider/narrower per counterparty)
//   volSprd       volatility risk buffer (widens under elevated vol)
//   smoothSprd    quote-stability smoothing (dampens jumps between quotes)
//   fallbackSprd  supplemental/fallback buffer, used when other inputs are thin
//   alphaSprd     directional-signal adjustment (model's market view)
// Order matters for .spread.waterfall (cumulative build, ref -> total).
.spread.componentCols:`refSprd`baseSprd`clientSprd`volSprd`smoothSprd`fallbackSprd`alphaSprd;

// canonical input shape: one row per quote. `weight` is whatever the
// caller wants to weight aggregates by (notional, time-alive, 1 for
// an unweighted average, ...). `aggression`/`marketStatus` are free-
// form regime tags (e.g. `low`medium`high, `normal`stressed`closed).
.spread.quote:([]
  time:`timestamp$(); sym:`symbol$(); aggression:`symbol$(); marketStatus:`symbol$();
  weight:`float$();
  refSprd:`float$(); baseSprd:`float$(); clientSprd:`float$(); volSprd:`float$();
  smoothSprd:`float$(); fallbackSprd:`float$(); alphaSprd:`float$());

//--------------------------------------------------------------------
// Compose / decompose / waterfall
//--------------------------------------------------------------------
//@func  | .spread.compose
//@param  | tab | 99 | table containing (at least) .spread.componentCols - keyed or not
//@desc
// add totalSprd as the row-wise sum of the named components. Safe to
// call on a table that already has totalSprd - it will be
// recomputed/overwritten. Works on a keyed source too (e.g. .spread.
// wavgBy's/.spread.byTime's output) - the column-only extraction below
// unkeys a temporary copy to read the components (bracket/`#` access
// on a keyed table means "look up this key value", not "get this
// column"), but the `update` that actually adds totalSprd runs against
// the original `tab`, so the result keeps tab's keyed-ness as is.
//@desc
.spread.compose:{[tab]
  cv:.spread.componentCols#0!tab;
  update totalSprd:sum value flip cv from tab
 };

//@func  | .spread.decompose
//@param  | tab | 99 | quote-shaped table, with or without totalSprd - keyed or not (e.g. .spread.byTime's/.spread.byRegime's output)
//@desc
// melt each row into one row per component, giving `component`
// (symbol) and `componentValue` (float) alongside the row's
// totalSprd, plus contributionBps and pctOfTotal - the shape to feed
// a stacked-bar / attribution chart. Composes totalSprd first if it
// isn't present. Unkeys first: a keyed source (any wavgBy/byTime/
// byRegime result) would otherwise break the column-select below,
// since keyed-table column selection doesn't behave like plain-table
// column selection. (Column is `componentValue`, not `value` - `value`
// is a q builtin and can't be an update-clause target.)
//@desc
.spread.decompose:{[tab]
  t:0!$[`totalSprd in cols tab;tab;.spread.compose tab];
  keyCols:cols[t] except .spread.componentCols,`totalSprd;
  parts:{[t;keyCols;c]
    r:keyCols#t;
    update component:c, componentValue:t[c], totalSprd:t[`totalSprd] from r
   }[t;keyCols] each .spread.componentCols;
  res:raze parts;
  update contributionBps:1e4*componentValue, pctOfTotal:100*componentValue%totalSprd from res
 };

//@func  | .spread.waterfall
//@param  | tab | 99 | quote-shaped table, with or without totalSprd - keyed or not
//@desc
// append one cumulative column per component (cum_refSprd,
// cum_refSprd+baseSprd, ... up to cum_alphaSprd), in componentCols
// order, so each row traces the running build from the reference
// spread up to the full quoted spread. cum_alphaSprd == totalSprd by
// construction - a handy invariant to assert in tests. Same keyed-
// table caveat as .spread.compose: the component extraction below
// unkeys a temporary copy to read columns, everything else runs
// against `t` itself so a keyed source stays keyed.
//@desc
.spread.waterfall:{[tab]
  t:$[`totalSprd in cols tab;tab;.spread.compose tab];
  rows:flip value flip .spread.componentCols#0!t;
  cum:flip sums each rows;
  cumCols:`$"cum_",/:string .spread.componentCols;
  t,'flip cumCols!cum
 };

//--------------------------------------------------------------------
// Aggregation
//--------------------------------------------------------------------
//@func  | .spread.priv.wavgAggCols
//@param  | wCols | 11 | value columns to weighted-average, symbol list
//@desc
// build the aggregate-column spec {col: (wavg;`weight;col)} for each
// wCols, plus summed weight - shared by .spread.wavgBy and
// .spread.byTime so both use one weighting convention. Built as one
// direct key-vector/value-vector zip rather than a per-column dict
// unioned via raze, so there's a single dict allocation regardless of
// how many columns are being aggregated.
//@desc
.spread.priv.wavgAggCols:{[wCols]
  (`weight,wCols)!enlist[(sum;`weight)],{(wavg;`weight;x)} each wCols
 };

//@func  | .spread.wavgBy
//@param  | tab | 99 | quote-shaped table, with or without totalSprd
//@param  | keyCols | 11 | grouping columns, symbol list (can be `$())
//@desc
// weight-average every component plus totalSprd by arbitrary key
// columns - e.g. `sym, `sym`aggression, or `$() for a single overall
// row. A single big quote shouldn't count the same as a small one,
// so this weights by `weight rather than a plain average.
//@desc
.spread.wavgBy:{[tab;keyCols]
  t:$[`totalSprd in cols tab;tab;.spread.compose tab];
  wCols:.spread.componentCols,`totalSprd;
  ?[t;();keyCols!keyCols;.spread.priv.wavgAggCols wCols]
 };

//@func  | .spread.util.timeBucket
//@param  | bucket | -11 | `month`week`date`hour`minute`second, or a timespan atom for a custom xbar size
//@param  | timeCol | -11 | symbol name of the time column to bucket
//@desc
// parse-tree for the requested time bucket, for use as a `by`-clause
// value in a functional ?[] select. Dispatches on what KIND of bucket
// it is rather than looking every bucket up in one flat table of
// pre-built parse-trees: a custom size goes straight to xbar; a
// calendar bucket (month/week/date) becomes a cast projection built
// from the bucket symbol itself (`` bucket$ ``, q's partial application
// of the $ cast operator); anything else is an xbar sized by a small
// duration lookup.
//@desc
.spread.util.timeBucket:{[bucket;timeCol]
  castBuckets:`month`week`date;
  sizeByBucket:`hour`minute`second!0D01 0D00:01 0D00:00:01;
  $[-16h=type bucket; (xbar;bucket;timeCol);
    bucket in castBuckets; (bucket$;timeCol);
    (xbar;sizeByBucket bucket;timeCol)]
 };

//@func  | .spread.byTime
//@param  | tab | 99 | quote-shaped table, with or without totalSprd
//@param  | bucket | -11 | `month`week`date`hour`minute`second, or a timespan atom
//@param  | extraKeyCols | 11 | additional grouping columns, symbol list (can be `$())
//@desc
// weight-averaged spread build-up rolled up by time bucket, optionally
// crossed with extra keys (e.g. `sym) - generalizes both a monthly/
// weekly spread report and a fine-grained intraday rollup into one
// call.
//@desc
.spread.byTime:{[tab;bucket;extraKeyCols]
  t:$[`totalSprd in cols tab;tab;.spread.compose tab];
  aggC:(extraKeyCols!extraKeyCols),enlist[`time]!enlist .spread.util.timeBucket[bucket;`time];
  wCols:.spread.componentCols,`totalSprd;
  ?[t;();aggC;.spread.priv.wavgAggCols wCols]
 };

//--------------------------------------------------------------------
// Percentile aggregation - a mean can look stable while the tail
// isn't; wavgBy/byTime only ever show the weighted center
//--------------------------------------------------------------------
//@func  | .spread.priv.wpctl
//@param  | p | -9 | target percentile as a fraction, 0-1 (0.5 for median, 0.9 for p90, ...)
//@param  | w | 11 | weight vector, same length as x
//@param  | x | 11 | value vector, same length as w
//@desc
// weighted percentile, nearest-rank method: sort by value, walk
// cumulative weight in that order, and return the value at the point
// the cumulative weight FRACTION first reaches p. Same shape as q's
// own `wavg` (weight, value in, one number out) so it drops straight
// into a functional-select aggregate spec the same way wavg does.
// Nearest-rank rather than interpolated: the returned value is always
// one that was actually observed, which is the usual convention for a
// VaR-style "worst X% single observation" read rather than a smoothed
// statistical estimate.
//@desc
.spread.priv.wpctl:{[p;w;x]
  ord:iasc x;
  cw:(sums w ord)%sum w;
  (x ord) first where cw>=p
 };

//@func  | .spread.priv.pctlAggCols
//@param  | percentiles | 9 | target percentiles as fractions, 0-1, float list (e.g. 0.5 0.9 0.99)
//@param  | valCol | -11 | the column to compute percentiles of
//@desc
// build the aggregate-column spec {pNN: (.spread.priv.wpctl;p;`weight;valCol)}
// for each requested percentile, column-named from the percentile
// itself (0.5 -> `p50, 0.99 -> `p99) - the percentile counterpart to
// .spread.priv.wavgAggCols.
//@desc
.spread.priv.pctlAggCols:{[percentiles;valCol]
  labels:`$"p",/:string `int$100*percentiles;
  labels!{[valCol;p] (.spread.priv.wpctl;p;`weight;valCol)}[valCol;] each percentiles
 };

//@func  | .spread.pctlBy
//@param  | tab | 99 | quote-shaped table, with or without totalSprd
//@param  | keyCols | 11 | grouping columns, symbol list (can be `$())
//@param  | percentiles | 9 | target percentiles as fractions, 0-1, float list (e.g. 0.5 0.9 0.99)
//@desc
// weighted percentiles of totalSprd by arbitrary key columns - the
// distributional counterpart to .spread.wavgBy. One row per key-column
// combination, one column per requested percentile (pNN).
//@desc
.spread.pctlBy:{[tab;keyCols;percentiles]
  t:$[`totalSprd in cols tab;tab;.spread.compose tab];
  ?[t;();keyCols!keyCols;.spread.priv.pctlAggCols[percentiles;`totalSprd]]
 };

//@func  | .spread.pctlByTime
//@param  | tab | 99 | quote-shaped table, with or without totalSprd
//@param  | bucket | -11 | `month`week`date`hour`minute`second, or a timespan atom
//@param  | extraKeyCols | 11 | additional grouping columns, symbol list (can be `$())
//@param  | percentiles | 9 | target percentiles as fractions, 0-1, float list (e.g. 0.5 0.9 0.99)
//@desc
// weighted percentiles of totalSprd rolled up by time bucket - the
// distributional counterpart to .spread.byTime, so a tail that's
// widening can be seen even while the weighted mean looks flat.
//@desc
.spread.pctlByTime:{[tab;bucket;extraKeyCols;percentiles]
  t:$[`totalSprd in cols tab;tab;.spread.compose tab];
  aggC:(extraKeyCols!extraKeyCols),enlist[`time]!enlist .spread.util.timeBucket[bucket;`time];
  ?[t;();aggC;.spread.priv.pctlAggCols[percentiles;`totalSprd]]
 };

//@func  | .spread.shareByTime
//@param  | tab | 99 | quote-shaped table, with or without totalSprd
//@param  | bucket | -11 | `month`week`date`hour`minute`second, or a timespan atom
//@param  | extraKeyCols | 11 | additional grouping columns, symbol list (can be `$())
//@desc
// each component's SHARE of the total spread, tracked over time - not
// "what's the average level of volSprd" (that's .spread.byTime) but
// "what fraction of the spread is volSprd responsible for, and does
// that change as the session goes on". Weight-averages each component
// and totalSprd per bucket first via .spread.byTime, THEN turns each
// bucket's shares into a fraction via .spread.decompose - deliberately
// in that order: a component's share in a bucket has to be the ratio
// of its own weighted average to the bucket's weighted total, not an
// average of each quote's individual pctOfTotal, since averaging
// ratios directly gives the wrong answer whenever weight varies within
// the bucket. One row per (time bucket, component); pctOfTotal sums to
// 100 within every bucket by construction.
//@desc
.spread.shareByTime:{[tab;bucket;extraKeyCols] .spread.decompose .spread.byTime[tab;bucket;extraKeyCols]};

//@func  | .spread.byRegime
//@param  | tab | 99 | quote-shaped table, with or without totalSprd
//@param  | regimeCols | 11 | the regime-tag columns to group by, symbol list (e.g. `aggression`marketStatus)
//@param  | extraKeyCols | 11 | additional grouping columns, symbol list (can be `$())
//@desc
// weight-averaged spread build-up by whatever regime tags the caller's
// schema actually has (optionally crossed with extra keys) - how the
// same nominal quote gets priced differently depending on what regime
// it was quoted in. A thin, named wrapper over .spread.wavgBy: it adds
// nothing regimeCols,extraKeyCols wouldn't already say on its own, but
// "by regime" documents intent at the call site in a way a bare column
// list doesn't.
//@desc
.spread.byRegime:{[tab;regimeCols;extraKeyCols] .spread.wavgBy[tab;regimeCols,extraKeyCols]};

//--------------------------------------------------------------------
// Reconciliation vs a reference/realized spread
//--------------------------------------------------------------------
//@func  | .spread.vsReference
//@param  | modelTab | 99 | quote-shaped table, with or without totalSprd
//@param  | refTab | 99 | independent spread series to compare against (e.g. realized market spread)
//@param  | keyCols | 11 | join keys common to both tables, symbol list
//@param  | refCol | -11 | name of refTab's spread value column
//@desc
// join the model's composed totalSprd against an independently
// sourced reference/realized spread on keyCols, and return how rich
// or cheap the model was, in both bps and pct. Useful for
// reconciling what a pricing model quoted against what the market
// (or a benchmark model) actually showed.
//@desc
.spread.vsReference:{[modelTab;refTab;keyCols;refCol]
  m:$[`totalSprd in cols modelTab;modelTab;.spread.compose modelTab];
  mSel:keyCols xkey ?[m;();0b;(keyCols!keyCols),enlist[`modelSprd]!enlist`totalSprd];
  rSel:keyCols xkey ?[refTab;();0b;(keyCols!keyCols),enlist[`refSprd]!enlist refCol];
  res:0!mSel,'rSel;
  update richnessBps:1e4*modelSprd-refSprd, richnessPct:100*(modelSprd-refSprd)%refSprd from res
 };

//--------------------------------------------------------------------
// Real-time path: latest snapshot per key
//--------------------------------------------------------------------
// unlike markout/impact, spread attribution needs no future data to
// resolve - a quote is fully explainable the instant it arrives. The
// real-time path is therefore just "keep the latest composed quote
// per key", not a pending/target-time match.
.spread.snap:update totalSprd:`float$() from
  ([sym:`symbol$(); aggression:`symbol$(); marketStatus:`symbol$()]
    time:`timestamp$(); weight:`float$();
    refSprd:`float$(); baseSprd:`float$(); clientSprd:`float$(); volSprd:`float$();
    smoothSprd:`float$(); fallbackSprd:`float$(); alphaSprd:`float$());

//@func  | .spread.onQuote
//@param  | q | 98 | single quote dict: sym, aggression, marketStatus, time, weight, plus .spread.componentCols
//@desc
// call on every new quote: compose its totalSprd and upsert it as the
// latest snapshot for its (sym, aggression, marketStatus) key.
//@desc
.spread.onQuote:{[q]
  t:`sym`aggression`marketStatus xkey .spread.compose enlist q;
  `.spread.snap upsert t
 };

//@func  | .spread.latest
//@desc
// current latest-per-key snapshot table, unkeyed for easy querying.
//@desc
.spread.latest:{[] 0!.spread.snap};

//====================================================================
// demo
//====================================================================
/ toy:([] time:2#.z.p; sym:`EURUSD`EURUSD; aggression:`low`high; marketStatus:`normal`stressed;
/   weight:1e6 2e6; refSprd:0.8 0.8; baseSprd:0.3 0.3; clientSprd:0.1 0.05;
/   volSprd:0.05 0.4; smoothSprd:0.02 0.02; fallbackSprd:0 0.1; alphaSprd:0.05 0.15);
/ .spread.compose toy;
/ .spread.decompose toy;
/ .spread.waterfall toy;
/ .spread.byRegime[toy;`aggression`marketStatus;`$()];
/ .spread.onQuote first toy; .spread.latest[];
//====================================================================