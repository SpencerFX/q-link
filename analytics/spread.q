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
//@param  | tab | 99 | table containing (at least) .spread.componentCols
//@desc
// add totalSprd as the row-wise sum of the named components. Safe to
// call on a table that already has totalSprd - it will be
// recomputed/overwritten.
//@desc
.spread.compose:{[tab]
  update totalSprd:sum value flip .spread.componentCols#tab from tab
 };

//@func  | .spread.decompose
//@param  | tab | 99 | quote-shaped table, with or without totalSprd
//@desc
// melt each row into one row per component, giving `component`
// (symbol) and `componentValue` (float) alongside the row's
// totalSprd, plus contributionBps and pctOfTotal - the shape to feed
// a stacked-bar / attribution chart. Composes totalSprd first if it
// isn't present. (Column is `componentValue`, not `value` - `value`
// is a q builtin and can't be an update-clause target.)
//@desc
.spread.decompose:{[tab]
  t:$[`totalSprd in cols tab;tab;.spread.compose tab];
  keyCols:cols[t] except .spread.componentCols,`totalSprd;
  parts:{[t;keyCols;c]
    r:keyCols#t;
    update component:c, componentValue:t[c], totalSprd:t[`totalSprd] from r
   }[t;keyCols] each .spread.componentCols;
  res:raze parts;
  update contributionBps:1e4*componentValue, pctOfTotal:100*componentValue%totalSprd from res
 };

//@func  | .spread.waterfall
//@param  | tab | 99 | quote-shaped table, with or without totalSprd
//@desc
// append one cumulative column per component (cum_refSprd,
// cum_refSprd+baseSprd, ... up to cum_alphaSprd), in componentCols
// order, so each row traces the running build from the reference
// spread up to the full quoted spread. cum_alphaSprd == totalSprd by
// construction - a handy invariant to assert in tests.
//@desc
.spread.waterfall:{[tab]
  t:$[`totalSprd in cols tab;tab;.spread.compose tab];
  rows:flip value flip .spread.componentCols#t;
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
// .spread.byTime so both use one weighting convention.
//@desc
.spread.priv.wavgAggCols:{[wCols]
  aCols:enlist[`weight]!enlist(sum;`weight);
  aCols,raze {enlist[x]!enlist(wavg;`weight;x)} each wCols
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
// value in a functional ?[] select.
//@desc
.spread.util.timeBucket:{[bucket;timeCol]
  presets:(`month`week`date`hour`minute`second)!(
    (`month$;timeCol);(`week$;timeCol);(`date$;timeCol);
    (xbar;0D01;timeCol);(xbar;0D00:01;timeCol);(xbar;0D00:00:01;timeCol));
  $[-16h=type bucket; (xbar;bucket;timeCol); presets bucket]
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

//@func  | .spread.byRegime
//@param  | tab | 99 | quote-shaped table, with or without totalSprd
//@param  | extraKeyCols | 11 | additional grouping columns, symbol list (can be `$())
//@desc
// weight-averaged spread build-up by aggression and marketStatus
// (optionally crossed with extra keys) - how the same nominal quote
// gets priced differently depending on how aggressively it was quoted
// and what regime the market was in.
//@desc
.spread.byRegime:{[tab;extraKeyCols] .spread.wavgBy[tab;`aggression`marketStatus,extraKeyCols]};

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
/ .spread.byRegime[toy;`$()];
/ .spread.onQuote first toy; .spread.latest[];
//====================================================================