//====================================================================
// Standalone functions: FX Markout & Market Impact
//
// General-purpose kdb+/q implementations of two
// post-trade/post-order price-deviation analyses:
//   .markout.*       - client DEAL markout: how the market mid moves
//                       relative to a trade's execution rate, at a
//                       grid of offsets from -10 minutes to +10 minutes.
//
//   .impact.*  - ORDER/EXECUTION impact: how the market book
//                       moves around an order's arrival, at a tighter
//                       grid from -10 seconds to +60 seconds, split
//                       into a temporary (peak) and permanent
//                       (post-decay) component.
//====================================================================

//--------------------------------------------------------------------
// Shared utilities
//--------------------------------------------------------------------
// offset grid (as floats, in seconds) from a strictly ascending
// vector of positive offsets. Returns a sorted vector with no
// duplicate-removal / sort step required downstream, since the
// input is assumed non-overlapping and ascending.
.util.buildGrid:{[posOffsets]
  pos:asc distinct posOffsets except 0f;
  (reverse neg pos),0f,pos 
 };

// .util.toTimespan[secs] - cast a vector/atom of fractional seconds
// to a q timespan, ready to add onto a timestamp column.
.util.toTimespan:{[secs] `timespan$1e9*secs};

// .util.explode[rows;timeCol;gridNS] - cross rows against a
// (pre-cast, invariant) timespan grid and compute the per-row
// target lookup time. `timeCol` is the SYMBOL name of the anchor-
// time column already present in `rows` (e.g. `tradeTime or
// `orderTime)
.util.explode:{[rows;timeCol;gridNS]
  crossed:rows cross ([]offset:gridNS);
  update targetTime:crossed[timeCol]+offset from crossed
 };

//--------------------------------------------------------------------
// .markout - client deal markout
//--------------------------------------------------------------------
// standard grid: sub-second near the trade, coarsening out to 10min
.markout.gridSecs:.util.buildGrid[(0.1*1+til 10),(2+til 14),30 60 120 180 300 600f];
.markout.gridNS:.util.toTimespan .markout.gridSecs;

// .markout.calc[trade;rate] - batch/ad-hoc markout calculation.
//   trade: ([] tradeID; tradeTime:`timestamp$(); tradeRate:`float$(); sym)
//   rate:  ([] time:`timestamp$(); sym; mid:`float$())  -- sorted by
//          time within sym, ideally with `p#sym and time sorted.
// Returns one row per trade, with nested `grids`/`markout` columns
// plus the matched rate timestamp (for staleness checks) and a
// stale flag.
.markout.calc:{[trade;rate]
  req:`sym`targetTime xasc .util.explode[trade;`tradeTime;.markout.gridNS];
  bk:update targetTime:time from rate;
  res:aj[`sym`targetTime; req; `sym`targetTime xasc `sym`targetTime`time`mid xcols bk];
  res:update
    markoutVal:mid-tradeRate,
    offsetSec:`float$(targetTime-tradeTime)%1e9,
    stale:(targetTime-time)>0D00:00:02
    from res;
  select grids:offsetSec, markoutVal, matchedTime:time, stale:stale by tradeID from res
 };

// .markout.calcDate[d;tradeGetter;rateGetter] - single-partition
// wrapper suitable for `peach` across dates (see .markout.calcAll).
.markout.calcDate:{[d;tradeGetter;rateGetter].markout.calc[tradeGetter d; rateGetter d]};

// .markout.calcAll[dates;tradeGetter;rateGetter] - parallelize the
// batch calc across independent dates. Benchmark with \ts before
// assuming peach wins at your typical daily row count.
.markout.calcAll:{[dates;tradeGetter;rateGetter] raze .markout.calcDate[;tradeGetter;rateGetter] peach dates};

// .markout.notionalWeighted[markoutTab;deals] - aggregate markout by
// sym and offset, weighted by trade notional rather than a plain
// average (a single large trade shouldn't count the same as a small
// one). `deals` supplies tradeID->notional/sym.
.markout.notionalWeighted:{[markoutRows;deals]
  j:(`tradeID xkey deals)[;`notional`sym] (`tradeID xkey markoutRows)`tradeID;
  t:update notional:j`notional, sym:j`sym from markoutRows;
  select markoutBps:1e4*wavg[notional;markoutVal] by sym,grids from t where not stale
 };

//--------------------------------------------------------------------
// .markout real-time (incremental) path
//--------------------------------------------------------------------
// working state: one row per (trade, offset) still awaiting a rate
.markout.pending:([tradeID:`long$(); offsetIdx:`int$()]sym:`symbol$(); targetTime:`timestamp$(); tradeRate:`float$());

.markout.completed:([tradeID:`long$(); offsetIdx:`int$()]offsetSec:`float$(); mid:`float$(); markoutVal:`float$(); matchedTime:`timestamp$());

// call on every new trade: register all offsets as pending
.markout.onTrade:{[tr]
  n:count .markout.gridSecs;
  rows:([]tradeID:n#tr`tradeID; offsetIdx:til n;
    sym:n#tr`sym; targetTime:tr[`tradeTime]+.markout.gridNS; tradeRate:n#tr`tradeRate);
  `.markout.pending upsert rows 
 };

// call on every new rate tick: complete any offsets now reachable
.markout.onRate:{[rt]
  hits:select from .markout.pending where sym=rt`sym, targetTime<=rt`time;
  if[count hits;
    `.markout.completed upsert update
      offsetSec:.markout.gridSecs offsetIdx,
      mid:rt`mid,
      markoutVal:rt[`mid]-tradeRate,
      matchedTime:rt`time
      from hits;
    delete from `.markout.pending where (tradeID;offsetIdx) in hits[`tradeID`offsetIdx]]
 };

//--------------------------------------------------------------------
// .impact - order/execution impact on the market book
//--------------------------------------------------------------------
// tighter grid: -10s..+60s, resolution biased toward the seconds
// immediately after the order rather than +/-10 minutes
.impact.gridSecs:.util.buildGrid[(0.5*1+til 20),(11+til 50)];
.impact.gridSecs:.impact.gridSecs where .impact.gridSecs>=-10;
.impact.gridNS:.util.toTimespan .impact.gridSecs;

// .impact.calc[orders;book] - batch calculation.
//   orders: ([] orderID; orderTime:`timestamp$(); orderRate:`float$();
//               sym; side:`symbol$())   / side: `buy`sell
//   book:   ([] time:`timestamp$(); sym; mid:`float$())
// Impact sign is normalized so a POSITIVE value always means the
// market moved in the direction the order pushed it (adverse for a
// buyer if positive, i.e. price kept rising after a buy).
.impact.calc:{[orders;book]
  req:`sym`targetTime xasc .util.explode[orders;`orderTime;.impact.gridNS];
  bk:`sym`targetTime xasc `targetTime xcol book;
  res:aj[`sym`targetTime; req; bk];
  res:update
    rawMove:mid-orderRate,
    offsetSec:`float$(targetTime-orderTime)%1e9,
    dirSign:?[side=`buy;1f;-1f]
    from res;
  update impact:dirSign*rawMove from res
 };

// .impact.decompose[calcRes;peakWindowSecs;permWindowSecs] -
// split each order's impact curve into a temporary (peak, within the
// first `peakWindowSecs) and permanent (average over the tail beyond
// `permWindowSecs) component - the standard temporary/permanent
// impact decomposition.
.impact.decompose:{[calcRes;peakWindowSecs;permWindowSecs]
  peak:select temporaryImpact:max impact by orderID from select from calcRes where offsetSec within (0;peakWindowSecs);
  perm:select permanentImpact:avg impact by orderID from select from calcRes where offsetSec>=permWindowSecs;
  peak lj perm
 };

// .impact.bySymSide[calcRes;orders] - aggregate mean impact by
// sym, side and offset - the shape you'd plot as an impact curve.
.impact.bySymSide:{[calcRes;orders]
  j:(`orderID xkey orders)[;`side`sym] (`orderID xkey calcRes)`orderID;
  t:update side:j`side, sym:j`sym from calcRes;
  select meanImpactBps:1e4*avg impact by sym,side,offsetSec from t
 };

//--------------------------------------------------------------------
// .impact real-time (incremental) path - same shape as markout
//--------------------------------------------------------------------
.impact.pending:([orderID:`long$(); offsetIdx:`int$()] sym:`symbol$(); side:`symbol$(); targetTime:`timestamp$(); orderRate:`float$());

.impact.completed:([orderID:`long$(); offsetIdx:`int$()] offsetSec:`float$(); mid:`float$(); impact:`float$(); matchedTime:`timestamp$());

.impact.onOrder:{[ord]
  n:count .impact.gridSecs;
  rows:([]orderID:n#ord`orderID; offsetIdx:til n;
    sym:n#ord`sym; side:n#ord`side;
    targetTime:ord[`orderTime]+.impact.gridNS; orderRate:n#ord`orderRate);
  `.impact.pending upsert rows
 };

.impact.onBook:{[bk]
  hits:select from .impact.pending where sym=bk`sym, targetTime<=bk`time;
  if[count hits;
    dirSign:?[hits[`side]=`buy;1f;-1f];
    `.impact.completed upsert update
      offsetSec:.impact.gridSecs offsetIdx,
      mid:bk`mid,
      impact:dirSign*(bk[`mid]-orderRate),
      matchedTime:bk`time
      from hits;
    delete from `.impact.pending where (orderID;offsetIdx) in hits[`orderID`offsetIdx]]
 };
//====================================================================