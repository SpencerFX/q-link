// Non-interactive test runner for analytics/markOutImpact.q
//   q test/testMarkOutImpact.q
// Exits 0 with "ALL TESTS PASSED" on success, throws (non-zero exit,
// stack trace on stderr) on the first failing assertion.

system"l ./analytics/markOutImpact.q";
system"l ./data/generator.q";

.test.assert:{[msg;cond] if[not cond;'"FAILED: ",msg]; -1"PASSED: ",msg;};

//--------------------------------------------------------------------
// .util.buildGrid: exact symmetric grid, dedupe + zero-drop
//--------------------------------------------------------------------
.test.assert["buildGrid: mirrors, sorts, and centers on 0";
  (.util.buildGrid[1 2 5f])~-5 -2 -1 0 1 2 5f];
.test.assert["buildGrid: drops duplicates and an explicit 0 from the input";
  (.util.buildGrid[0 1 1 2f])~-2 -1 0 1 2f];

//--------------------------------------------------------------------
// .util.toTimespan: exact cast, vector and atom
//--------------------------------------------------------------------
.test.assert["toTimespan: atom cast to timespan exactly";
  (.util.toTimespan[1.5])~0D00:00:01.500000000];
.test.assert["toTimespan: vector cast preserves sign and order";
  (.util.toTimespan[-1 0 1f])~-0D00:00:01 0D00:00:00 0D00:00:01];

//--------------------------------------------------------------------
// .util.explode: cross against grid, targetTime = anchor + offset
//--------------------------------------------------------------------
t0:.z.p;
rows1:([]tradeTime:enlist t0);
grid3:.util.toTimespan[-1 0 1f];
ex:.util.explode[rows1;`tradeTime;grid3];
.test.assert["explode: one row per grid offset";3=count ex];
.test.assert["explode: targetTime is anchor + offset, exactly";
  (asc ex`targetTime)~asc t0+grid3];

//--------------------------------------------------------------------
// .markout.calc: exact join + staleness logic against the REAL
// production grid (.markout.gridSecs), using just two rate ticks -
// one placed before every negative offset's target, one placed
// exactly at the trade time. Because aj (as-of join) always matches
// the latest tick at-or-before targetTime, every negative-offset row
// matches the early tick and every non-negative-offset row matches
// the at-t0 tick - deterministic and exact across all ~61 grid rows,
// no synthetic noise involved.
//--------------------------------------------------------------------
mkTradeRate:1.1000;
mkMidA:1.0500;   / matches every negative-offset row
mkMidB:1.1010;   / matches every non-negative-offset row (tick sits exactly at t0)
mkTrade:([]tradeID:enlist 1; tradeTime:enlist t0; tradeRate:enlist mkTradeRate; sym:enlist`EURUSD);
mkRate:([]time:t0-0D00:20:00 0D00:00:00; sym:2#`EURUSD; mid:mkMidA,mkMidB);
mkRes:0!ungroup 0!.markout.calc[mkTrade;mkRate];

.test.assert["markout.calc: every grid row matched, no nulls";
  (count mkRes)=(not any null mkRes`markoutVal)*count mkRes];
.test.assert["markout.calc: matches the real production grid size";
  (count mkRes)=count .markout.gridSecs];

expMarkout:?[mkRes[`grids]<0f; mkMidA-mkTradeRate; mkMidB-mkTradeRate];
.test.assert["markout.calc: markoutVal exact for every offset (negative->tick A, >=0->tick B)";
  all 1e-9>abs mkRes[`markoutVal]-expMarkout];

expStale:(mkRes[`grids]<0f) or mkRes[`grids]>2f;
.test.assert["markout.calc: stale exactly matches (negative offsets, or >2s gap on the at-t0 tick)";
  all expStale=mkRes`stale];

//--------------------------------------------------------------------
// .markout.notionalWeighted: exact notional-weighted average at one
// bucket, and confirms an all-stale bucket is dropped, not nulled
//--------------------------------------------------------------------
nwTrade:([]
  tradeID:1 2; tradeTime:2#t0; tradeRate:1.1000 1.1020; sym:2#`EURUSD);
nwRes:.markout.calc[nwTrade;mkRate];
nwDeals:([]tradeID:1 2; sym:2#`EURUSD; notional:1e6 3e6);
nw:0!.markout.notionalWeighted[nwRes;nwDeals];

/ trade1 markoutVal@0 = 1.1010-1.1000 = 0.0010, notional 1e6
/ trade2 markoutVal@0 = 1.1010-1.1020 = -0.0010, notional 3e6
/ wavg = (1e6*0.0010 + 3e6*-0.0010) / 4e6 = -0.0005 -> bps = -5.0
.test.assert["notionalWeighted: exact notional-weighted bps at offset 0";
  1e-6>abs -5.0-first exec markoutBps from nw where sym=`EURUSD,grids=0f];
.test.assert["notionalWeighted: an all-stale bucket (max offset) is absent, not null";
  0=count select from nw where grids=max .markout.gridSecs];

//--------------------------------------------------------------------
// .markout real-time path: onTrade / onRate / sweepPending, sized
// dynamically off .markout.gridSecs / .markout.pendingTTL rather than
// hardcoded counts, so the test stays correct if the grid changes.
//--------------------------------------------------------------------
.markout.pending:0#.markout.pending; .markout.completed:0#.markout.completed;
nTotal:count .markout.gridSecs;
nNonPos:sum .markout.gridSecs<=0f;
nPos:sum .markout.gridSecs>0f;

rtTrade:`tradeID`tradeTime`tradeRate`sym!(9;t0;1.1000;`EURUSD);
.markout.onTrade rtTrade;
.test.assert["onTrade: registers exactly one pending row per grid offset";
  nTotal=count .markout.pending];

.markout.onRate `sym`time`mid!(`EURUSD;t0;1.1005);
.test.assert["onRate: completes exactly the non-positive-offset rows (targetTime<=t0)";
  nNonPos=count .markout.completed];
.test.assert["onRate: leaves exactly the positive-offset rows pending";
  nPos=count .markout.pending];

.markout.pending:0#.markout.pending; .markout.completed:0#.markout.completed;
.markout.onTrade rtTrade;
ttlSecs:`float$.markout.pendingTTL%1e9;
expEvicted:sum .markout.gridSecs<neg ttlSecs;
.markout.sweepPending t0;
.test.assert["sweepPending: evicts exactly the offsets older than pendingTTL, no more/less";
  (nTotal-expEvicted)=count .markout.pending];
.markout.pending:0#.markout.pending;

//--------------------------------------------------------------------
// .impact.calc: same two-tick exactness trick as markout.calc, plus
// the buy/sell sign-normalization invariant - a positive impact
// always means the market moved in the direction the order pushed it
//--------------------------------------------------------------------
imOrderRate:1.1000;
imMidA:1.0500;
imMidB:1.1010;
imOrders:([]orderID:1 2; orderTime:2#t0; orderRate:2#imOrderRate; sym:2#`EURUSD; side:`buy`sell);
imBook:([]time:t0-0D00:20:00 0D00:00:00; sym:2#`EURUSD; mid:imMidA,imMidB);
imRes:0!.impact.calc[imOrders;imBook];

.test.assert["impact.calc: every grid row matched, no nulls";
  not any null imRes`impact];
buyZero:first exec impact from imRes where orderID=1,offsetSec=0f;
sellZero:first exec impact from imRes where orderID=2,offsetSec=0f;
.test.assert["impact.calc: buy impact at offset 0 is mid-orderRate exactly";
  1e-9>abs buyZero-(imMidB-imOrderRate)];
.test.assert["impact.calc: sell impact is the exact negation of buy's for the same move";
  1e-9>abs sellZero-neg buyZero];

//--------------------------------------------------------------------
// .impact.decompose: hand-built impact curve, exact peak/permanent
//--------------------------------------------------------------------
/ peak window (0,10]: offsets 2,5,10 -> impact .006 .008 .004 -> max .008
/ perm window >=30 : single point at offset 40 -> avg .0035
decIn:([]orderID:6#1; offsetSec:-5 0 2 5 10 40f; impact:0.001 0.002 0.006 0.008 0.004 0.0035);
dec:.impact.decompose[decIn;10;30];
.test.assert["decompose: temporaryImpact is the exact max within (0,peakWindow]";
  1e-9>abs 0.008-first exec temporaryImpact from dec where orderID=1];
.test.assert["decompose: permanentImpact is the exact avg beyond permWindow (single point here)";
  1e-9>abs 0.0035-first exec permanentImpact from dec where orderID=1];

//--------------------------------------------------------------------
// .impact.bySymSide: exact mean-impact-bps at one (sym,side,offset)
//--------------------------------------------------------------------
bsCalc:([]orderID:1 2; sym:2#`EURUSD; offsetSec:2#5f; impact:0.001 0.003);
bsOrders:([]orderID:1 2; side:`buy`buy; sym:2#`EURUSD);
bs:.impact.bySymSide[bsCalc;bsOrders];
.test.assert["bySymSide: meanImpactBps is 1e4*avg(impact) for the bucket";
  1e-6>abs (1e4*avg 0.001 0.003)-first exec meanImpactBps from bs where sym=`EURUSD,side=`buy,offsetSec=5f];

//--------------------------------------------------------------------
// .impact real-time path: onOrder / onBook / sweepPending, sized
// dynamically off .impact.gridSecs / .impact.pendingTTL
//--------------------------------------------------------------------
.impact.pending:0#.impact.pending; .impact.completed:0#.impact.completed;
inTotal:count .impact.gridSecs;
inNonPos:sum .impact.gridSecs<=0f;
inPos:sum .impact.gridSecs>0f;

rtOrder:`orderID`orderTime`orderRate`sym`side!(9;t0;1.1000;`EURUSD;`buy);
.impact.onOrder rtOrder;
.test.assert["onOrder: registers exactly one pending row per grid offset";
  inTotal=count .impact.pending];

.impact.onBook `sym`time`mid!(`EURUSD;t0;1.1005);
.test.assert["onBook: completes exactly the non-positive-offset rows";
  inNonPos=count .impact.completed];
.test.assert["onBook: leaves exactly the positive-offset rows pending";
  inPos=count .impact.pending];

.impact.pending:0#.impact.pending; .impact.completed:0#.impact.completed;
.impact.onOrder rtOrder;
inTtlSecs:`float$.impact.pendingTTL%1e9;
inExpEvicted:sum .impact.gridSecs<neg inTtlSecs;
.impact.sweepPending t0;
.test.assert["impact.sweepPending: evicts exactly the offsets older than pendingTTL, no more/less";
  (inTotal-inExpEvicted)=count .impact.pending];
.impact.pending:0#.impact.pending;

//--------------------------------------------------------------------
// Synthetic ground truth: .synth.buildScenario's five injected impact
// events (known tempBps/permBps/halfLifeSecs) recovered by
// .impact.calc + .impact.decompose, and a driftless rate series'
// batch markout confirmed statistically indistinguishable from zero
//--------------------------------------------------------------------
scenario:.synth.buildScenario[];
rec:.synth.checkImpactRecovery[scenario;.impact.calc;.impact.decompose];
gt:0!scenario`groundTruth;
.test.assert["synthetic: every injected event has tempBps > permBps in ground truth (sanity on the fixture itself)";
  all gt[`tempBps]>gt[`permBps]];
.test.assert["synthetic: recovered temporaryImpactBps > recovered permanentImpactBps for every event";
  all 0<exec temporaryImpactBps-permanentImpactBps from rec];
/ Each event is a single order riding one noisy GBM path - unlike the
/ driftless-markout check below (averaged over 500 trades), there's no
/ law-of-large-numbers smoothing here, so per-event relative error on a
/ few-bps ground truth is genuinely noisy (observed up to ~110% on this
/ fixed default seed). A loose order-of-magnitude bound still catches a
/ genuinely broken decompose (wrong scale, sign flip, wrong window) without
/ being a flaky tight bound on single-sample noise.
relErr:abs (rec[`temporaryImpactBps]-gt`tempBps)%gt`tempBps;
.test.assert["synthetic: recovered temporaryImpactBps within the right order of magnitude for every event";
  all relErr<2.0];

driftless:.synth.genRateSeries[`EURUSD;.z.p-0D01:00:00;3600;0.5;1.1000;0f;2e-5];
driftlessTrades:.synth.genTrades[`EURUSD;500;driftless;0.3];
dmk:0!ungroup 0!.markout.calc[driftlessTrades;driftless];
dmk:select from dmk where not stale, grids=max .markout.gridSecs;
se:(dev dmk`markoutVal)%sqrt count dmk;
.test.assert["synthetic: driftless (mu=0) markout mean at the max offset is within 4 standard errors of 0";
  (abs avg dmk`markoutVal)<4*se];

-1 "";
-1 "ALL TESTS PASSED";
exit 0
