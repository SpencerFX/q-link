//====================================================================
// Synthetic data generator (GBM) for testing .markout / .impact
//
// Generates a reference mid-rate series via Geometric Brownian
// Motion, plus matching trade and order tables, with the option to
// inject a KNOWN market-impact signature (temporary + permanent,
// with an exponential decay) around chosen orders. This lets you
// validate .marketImpact.decompose against ground truth rather than
// just eyeballing plausible-looking output.
//
// Depends on nothing else to RUN, but the demo section at the bottom
// assumes .markout.* / .impact.* / .util.explode etc. from the
// companion "markOutImpact.q" are already loaded.
//====================================================================

//--------------------------------------------------------------------
// Random normals (Box-Muller) - base q has no native Gaussian sampler
//--------------------------------------------------------------------
.util.randNorm:{[n]
  u1:1e-10+(1-1e-10)*n?1f;
  u2:n?1f;
  sqrt[-2*log u1]*cos[2*acos[-1]*u2]
 };

//--------------------------------------------------------------------
// GBM path
//--------------------------------------------------------------------
// .gbm.path[s0;mu;sigma;dtSecs;n] - n-step GBM price path.
//   s0    starting price
//   mu    annualized-style drift, expressed per SECOND (small, e.g. 0)
//   sigma volatility, also per second
//   dtSecs step size in seconds
//   n     number of steps (path length is n+1 including s0)
.gbm.path:{[s0;mu;sigma;dtSecs;n]
  z:.util.randNorm[n];
  logIncr:(mu-0.5*sigma*sigma)*dtSecs + sigma*sqrt[dtSecs]*z;
  s0*prds exp logIncr
 };

//--------------------------------------------------------------------
// Rate series
//--------------------------------------------------------------------
// .synth.genRateSeries[sym;startTime;durationSecs;dtSecs;s0;mu;sigma]
// -> ([] time; sym; mid)   sorted by construction.
.synth.genRateSeries:{[sym;startTime;durationSecs;dtSecs;s0;mu;sigma]
  n:`long$durationSecs%dtSecs;
  times:startTime+`timespan$(`long$1e9*dtSecs)*til n;
  mids:.gbm.path[s0;mu;sigma;dtSecs;n];
  ([]time:times; sym:n#sym; mid:mids)
 };

//--------------------------------------------------------------------
// Trades, sampled off a rate series (for .markout testing)
//--------------------------------------------------------------------
// .synth.genTrades[sym;n;rateTab;spreadBps] - n trades at random
// existing tick times, rate = that tick's mid plus uniform noise in
// +/- spreadBps (crude bid/ask/slippage stand-in). With a driftless
// rateTab (mu=0), expected markout at every offset is ~0 for a large
// enough n - useful as a null-hypothesis sanity check. With mu!=0,
// expected markout at offset D is approximately mu*D.
.synth.genTrades:{[sym;n;rateTab;spreadBps]
  sub:select from rateTab where sym=sym;
  idx:n?count sub;
  base:sub idx;
  noise:1+(spreadBps*1e-4)*-1+2*n?1f;
  ([]tradeID:til n; tradeTime:base`time; tradeRate:base[`mid]*noise; sym:n#sym) }

//--------------------------------------------------------------------
// Market-impact injection - bakes a KNOWN temp/perm signature into
// the rate series following a chosen order time, so you can check
// .marketImpact.decompose recovers it.
//--------------------------------------------------------------------
// impact curve in bps: starts at tempBps at tau=0, decays
// exponentially (given half-life) down toward permBps as tau grows.
.synth.impactCurveBps:{[tau;tempBps;permBps;halfLifeSecs]
  permBps+(tempBps-permBps)*exp neg(log 2)*(0|tau)%halfLifeSecs 
 };

// .synth.injectImpact[rateTab;orderTime;sym;dirSign;tempBps;permBps;halfLifeSecs]
// -> rateTab with mid multiplicatively bumped for sym at/after
// orderTime. dirSign should be +1 for a buy (pushes price up) or -1
// for a sell. Only rows for the given sym at or after orderTime are
// touched; everything else passes through unchanged.
.synth.injectImpact:{[rateTab;orderTime;sym;dirSign;tempBps;permBps;halfLifeSecs]
  mask:(rateTab[`sym]=sym) and rateTab[`time]>=orderTime;
  tau:`float$(rateTab[`time]-orderTime)%1e9;
  bump:dirSign*.synth.impactCurveBps[tau;tempBps;permBps;halfLifeSecs]*1e-4;
  update mid:mid*(1+mask*bump) from rateTab
 };

// .synth.injectImpacts[rateTab;spec] - apply a whole table of planned
// injections in one call. spec: ([] orderTime;sym;dirSign;tempBps;
// permBps;halfLifeSecs). Space orderTimes far enough apart (well
// beyond your market-impact grid's max offset) so injections for the
// same sym don't overlap and contaminate each other.
.synth.injectImpacts:{[rateTab;spec]
  {[rt;row] .synth.injectImpact[rt;row`orderTime;row`sym;row`dirSign;
    row`tempBps;row`permBps;row`halfLifeSecs]}/[rateTab;spec] 
 };

// .synth.ordersFromSpec[spec;baselineRateTab] - build the orders
// table .marketImpact.calc expects, using orderRate captured from a
// PRE-injection snapshot of the rate series (i.e. what you actually
// would have traded at, before your own footprint moved anything).
// .synth.getMid[rt;sym;t] - last known mid for sym at/before time t.
// Defined as a proper namespaced function (not a local inside
// ordersFromSpec) because a LOCAL helper referenced from inside an
// each/peach/over-iterated lambda loses visibility: those iterators
// insert their own stack frame between the defining function and
// the lambda, and q's local-variable visibility only reaches one
// level up. Global names don't have that problem.
.synth.getMid:{[rt;sym;t] last (select mid from rt where sym=sym,time<=t)`mid};

.synth.ordersFromSpec:{[spec;baselineRateTab]
  rates:{[rt;row] .synth.getMid[rt;row`sym;row`orderTime]}[baselineRateTab;] each spec;
  ([]orderID:til count spec; orderTime:spec`orderTime; orderRate:rates; sym:spec`sym; side:?[spec[`dirSign]=1f;`buy;`sell]) 
 };

//--------------------------------------------------------------------
// End-to-end scenario builder
//--------------------------------------------------------------------
// .synth.buildScenario[] - one call that returns a dictionary with:
//   rate         the (impact-injected) reference rate series
//   trades       trades sampled for .markout testing
//   orders       orders matching the injected impact events
//   groundTruth  the known temp/perm parameters used, for comparison
//                against what .marketImpact.decompose recovers
.synth.buildScenario:{[]
  sym:`EURUSD;
  start:.z.p - 0D06:00:00;      / 6-hour synthetic session
  dtSecs:0.5;                   / tick every 500ms

  // baseline path: mild drift so markout has a non-zero, checkable
  // expected value (expected markout at offset D ~ mu*D)
  base:.synth.genRateSeries[sym;start;6*60*60;dtSecs;1.1000;5e-8;2e-5];

  // plan five well-separated impact events, alternating buy/sell,
  // spaced 40 minutes apart so their 60s-max impact windows never overlap
  orderTimes:start+`timespan$1e9*40*60*1+til 5;
  spec:([] orderTime:orderTimes; sym:5#sym;
    dirSign:1 -1 1 -1 1f;
    tempBps:3.5 5.0 2.0 6.5 4.0;
    permBps:1.0 2.5 0.2 3.0 1.5;
    halfLifeSecs:8 15 5 20 10f);

  orders:.synth.ordersFromSpec[spec;base];
  rate:.synth.injectImpacts[base;spec];
  trades:.synth.genTrades[sym;2000;base;0.3];

  `rate`trades`orders`groundTruth!(rate;trades;orders;spec) 
 };

// .synth.checkImpactRecovery[scenario;decomposeFn] - convenience: run
// your .marketImpact.calc + .marketImpact.decompose over the
// generated scenario and compare recovered temp/perm impact (in bps)
// against the injected ground truth, side by side.
.synth.checkImpactRecovery:{[scenario;calcFn;decomposeFn]
  calcRes:calcFn[scenario`orders;scenario`rate];
  rec:decomposeFn[calcRes;10;30];      / 10s peak window, 30s+ = permanent
  rec:update temporaryImpactBps:1e4*temporaryImpact,
    permanentImpactBps:1e4*permanentImpact from rec;
  gt:update orderID:til count scenario`groundTruth from scenario`groundTruth;
  gt lj `orderID xkey select orderID,temporaryImpactBps,permanentImpactBps from rec 
 };

//====================================================================
// demo (uncomment to run once markOutImpact.q is loaded)
//====================================================================
/ scenario:.synth.buildScenario[];
/ scenario`groundTruth;   / injected truth;
/ .synth.checkImpactRecovery[scenario;.impact.calc;.impact.decompose]
/ .markout.calc[scenario`trades;scenario`rate]                 / markout on synthetic trades
//====================================================================