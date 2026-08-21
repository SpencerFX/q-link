//====================================================================
// Synthetic data generator for testing .spread.* (analytics/spread.q)
//
// Generates a stream of pricing-engine spread quotes across currency
// pairs, aggression levels, and market-status regimes, with KNOWN
// injected effects:
//   - a stress multiplier applied to volSprd when marketStatus is
//     `stressed (first half of the session is `normal, second half
//     is `stressed, so the transition is also visible in a time
//     rollup)
//   - an aggression tightening factor applied to baseSprd/clientSprd
//     (more aggressive pricing -> tighter spread)
//   - an independent benchmark spread series with a KNOWN constant
//     richness offset baked in, for testing .spread.vsReference
//
// Because these effects are specified in advance, .spread.byRegime /
// .spread.byTime / .spread.vsReference can be checked against a known
// number rather than relying on eyeballing plausible-looking output.
//
// Depends on nothing to RUN, but the demo/check section at the bottom
// assumes analytics/spread.q is already loaded.
//====================================================================

//--------------------------------------------------------------------
// Random normals (Box-Muller) - base q has no native Gaussian sampler
//--------------------------------------------------------------------
//@func  | .spreadSynth.priv.randNorm
//@param  | n | long
//@desc
// generate n standard-normal samples via Box-Muller transform.
//@desc
.spreadSynth.priv.randNorm:{[n]
  u1:1e-10+(1-1e-10)*n?1f;
  u2:n?1f;
  sqrt[-2*log u1]*cos[2*acos[-1]*u2]
 };

//--------------------------------------------------------------------
// Config - the knobs that define the ground truth
//--------------------------------------------------------------------
.spreadSynth.config.syms:`EURUSD`GBPUSD`USDJPY;
// baseline (unstressed, low-aggression, LOW=1.0x) total spread scale per sym
.spreadSynth.config.baseLevelBySym:.spreadSynth.config.syms!0.8 1.0 0.9;

.spreadSynth.config.aggression:`low`medium`high;
// how much aggression tightens baseSprd/clientSprd: high aggression == tighter
.spreadSynth.config.aggressionMult:.spreadSynth.config.aggression!1.0 0.7 0.4;

// known multiplier applied to volSprd when marketStatus=`stressed
.spreadSynth.config.stressVolMult:4.0;

// known offset (price units) by which the model quotes richer than
// the independent benchmark reference, on average
.spreadSynth.config.injectedRichness:0.05;

//--------------------------------------------------------------------
// Session builder
//--------------------------------------------------------------------
//@func  | .spreadSynth.genSession
//@param  | start | -12 | session start time, timestamp atom
//@param  | nPerRegime | -7 | quote count for each of the normal/stressed halves, long atom
//@param  | dtSecs | -9 | average time between quotes, float atom
//@desc
// -> dict `quotes`benchmark`groundTruth. `quotes` is time-sorted with
// the first nPerRegime rows marketStatus=`normal and the next
// nPerRegime rows marketStatus=`stressed, so both a regime rollup and
// a time rollup can recover the same injected stress effect.
// `benchmark` is an independently-sourced spread series (time,sym,
// benchmarkSprd) built from quotes' totalSprd minus the known
// injectedRichness plus noise, for testing .spread.vsReference.
//@desc
.spreadSynth.genSession:{[start;nPerRegime;dtSecs]
  n:2*nPerRegime;
  totalSecs:n*dtSecs;
  times:asc start+`timespan$1e9*totalSecs*n?1f;
  marketStatus:(nPerRegime#`normal),nPerRegime#`stressed;
  sym:.spreadSynth.config.syms n?count .spreadSynth.config.syms;
  aggression:.spreadSynth.config.aggression n?count .spreadSynth.config.aggression;
  aggrFactor:.spreadSynth.config.aggressionMult aggression;
  baseLevel:.spreadSynth.config.baseLevelBySym sym;

  noise:{[k] 1+0.05*.spreadSynth.priv.randNorm[k]};

  stressFactor:?[marketStatus=`stressed;.spreadSynth.config.stressVolMult;1f];

  refSprd:baseLevel*noise[n];
  baseSprd:0.4*baseLevel*aggrFactor*noise[n];
  clientSprd:0.15*baseLevel*aggrFactor*noise[n];
  volSprd:0.1*baseLevel*stressFactor*noise[n];
  smoothSprd:0.02*baseLevel*noise[n];
  fallbackSprd:0.01*baseLevel*noise[n];
  alphaSprd:0.05*baseLevel*noise[n];
  weight:1e5+1e6*n?1f;

  quotes:.spread.compose ([]
    time:times; sym; aggression; marketStatus; weight;
    refSprd; baseSprd; clientSprd; volSprd; smoothSprd; fallbackSprd; alphaSprd);

  richness:.spreadSynth.config.injectedRichness;
  benchmark:update benchmarkSprd:totalSprd-richness+0.01*.spreadSynth.priv.randNorm[n]
    from select time,sym,totalSprd from quotes;

  groundTruth:`stressVolMult`injectedRichness!(.spreadSynth.config.stressVolMult;richness);

  `quotes`benchmark`groundTruth!(quotes;benchmark;groundTruth)
 };

//--------------------------------------------------------------------
// Recovery check - compare what .spread.* recovers against the
// injected ground truth
//--------------------------------------------------------------------
//@func  | .spreadSynth.checkRecovery
//@param  | scenario | 99 | dict returned by .spreadSynth.genSession
//@desc
// -> a table of named checks: expected (injected) value, recovered
// (estimated by .spread.*) value, relative error, and whether it's
// within tolerance. Two independent checks:
//   stressVolMult    - recovered via .spread.wavgBy grouped by
//                       marketStatus alone (volSprd[stressed]/volSprd[normal])
//   richnessBps       - recovered via .spread.vsReference against the
//                       synthetic benchmark series (avg richnessBps)
//@desc
.spreadSynth.checkRecovery:{[scenario]
  q:scenario`quotes; gt:scenario`groundTruth;

  // .spread.wavgBy's group-by already returns a table keyed by marketStatus
  byStatus:.spread.wavgBy[q;enlist`marketStatus];
  recStressMult:byStatus[enlist`stressed;`volSprd]%byStatus[enlist`normal;`volSprd];

  cmp:.spread.vsReference[q;scenario`benchmark;`time`sym;`benchmarkSprd];
  recRichnessBps:avg exec richnessBps from cmp;
  expRichnessBps:1e4*gt`injectedRichness;

  checks:([]
    check:`stressVolMult`richnessBps;
    expected:(gt`stressVolMult;expRichnessBps);
    recovered:(recStressMult;recRichnessBps));
  update relErrPct:100*abs[recovered-expected]%expected,
    pass:5>100*abs[recovered-expected]%expected
    from checks
 };

//====================================================================
// demo
//====================================================================
/ scenario:.spreadSynth.genSession[.z.p-0D02:00:00;2000;1.8];
/ scenario`groundTruth;
/ .spreadSynth.checkRecovery scenario;
/ .spread.byRegime[scenario`quotes;`aggression`marketStatus;`$()];
/ .spread.byTime[scenario`quotes;`minute;`$()];
//====================================================================