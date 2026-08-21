// Non-interactive test runner for analytics/spread.q
//   q test/testSpread.q
// Exits 0 with "ALL TESTS PASSED" on success, throws (non-zero exit,
// stack trace on stderr) on the first failing assertion.

system"l ./analytics/spread.q";
system"l ./data/spreadGenerator.q";

.test.assert:{[msg;cond] if[not cond;'"FAILED: ",msg]; -1"PASSED: ",msg;};

toy:([]
  time:.z.p+0D00:00:00 0D00:00:01; sym:`EURUSD`EURUSD; aggression:`low`high; marketStatus:`normal`stressed;
  weight:1e6 2e6; refSprd:0.8 0.8; baseSprd:0.3 0.3; clientSprd:0.1 0.05;
  volSprd:0.05 0.4; smoothSprd:0.02 0.02; fallbackSprd:0 0.1; alphaSprd:0.05 0.15);

// --- .spread.compose: totalSprd is the exact row-wise sum ---
composed:.spread.compose toy;
expectedTotal:0.8+0.3+0.1+0.05+0.02+0+0.05;
.test.assert["compose: totalSprd matches manual sum for row 0";1e-9>abs expectedTotal-first composed`totalSprd];

// --- .spread.waterfall: final cumulative column equals totalSprd exactly ---
wf:.spread.waterfall toy;
.test.assert["waterfall: cum_alphaSprd == totalSprd for every row";all wf[`cum_alphaSprd]=wf[`totalSprd]];

// --- .spread.decompose: componentValue sums back to totalSprd per row ---
dc:.spread.decompose toy;
sumBack:0!select componentValue:sum componentValue by time,sym from dc;
merged:sumBack lj `time`sym xkey select time,sym,totalSprd from composed;
.test.assert["decompose: componentValue sums back to totalSprd";all 1e-9>abs merged[`componentValue]-merged[`totalSprd]];

// --- .spread.byRegime: single-row-per-group weighted avg equals the input (n=1 per group here) ---
br:.spread.byRegime[toy;`aggression`marketStatus;`$()];
.test.assert["byRegime: wavg of a single row returns that row's value";
  (1e-9>abs 0.8-exec first refSprd from br where aggression=`low) and
  (1e-9>abs 0.4-exec first volSprd from br where aggression=`high)];

// --- .spread.vsReference: richness recovered exactly for a hand-built pair ---
ref:([]sym:enlist`EURUSD;benchmarkSprd:enlist 1.0);
vr:.spread.vsReference[select from toy where sym=`EURUSD,aggression=`low;ref;enlist`sym;`benchmarkSprd];
.test.assert["vsReference: richnessBps == 1e4*(totalSprd-benchmarkSprd)";1e-6>abs (first vr`richnessBps)-1e4*1.32-1.0];

// --- .spread.priv.wpctl: exact nearest-rank weighted percentile on a hand-built pair ---
// toy's two rows compose to totalSprd 1.32 (weight 1e6) and 1.82 (weight 2e6);
// cumulative weight fraction is 1/3 at 1.32 and 1.0 at 1.82, so ANY percentile
// >=1/3 (including the median) should land on the heavier, higher row
p:0!.spread.pctlBy[toy;`$();0.5 0.9 0.99];
.test.assert["pctlBy: p50/p90/p99 all land on the heavier row exactly";
  all 1e-9>abs 1.82-p[0;`p50`p90`p99]];

// --- .spread.pctlBy/.spread.pctlByTime: percentiles must be non-decreasing
// (p50<=p90<=p99) on every group/bucket - a basic sanity invariant of any
// correct percentile implementation, checked against real synthetic data ---
scenarioForPctl:.spreadSynth.genSession[.z.p-0D02:00:00;1000;1.5];
byMS:0!.spread.pctlBy[scenarioForPctl`quotes;enlist`marketStatus;0.5 0.9 0.99];
.test.assert["pctlBy: p50<=p90<=p99 in every group";all (byMS[`p50]<=byMS[`p90]) and byMS[`p90]<=byMS[`p99]];
byT:0!.spread.pctlByTime[scenarioForPctl`quotes;`minute;`$();0.5 0.9 0.99];
.test.assert["pctlByTime: p50<=p90<=p99 in every bucket";all (byT[`p50]<=byT[`p90]) and byT[`p90]<=byT[`p99]];

// --- .spread.compose/.spread.waterfall/.spread.decompose must all work on a KEYED
// source too (e.g. .spread.byTime's own output), not just raw unkeyed quotes -
// regression test: bracket/`#` column access on a keyed table means "look up
// this key value", not "get this column", and all three used to break on one ---
byT:.spread.byTime[toy;`second;`$()];
.test.assert["compose: works on keyed input and preserves keyed-ness";99h=type .spread.compose byT];
.test.assert["waterfall: works on keyed input";all not null exec cum_alphaSprd from .spread.waterfall byT];
.test.assert["decompose: works on keyed input";0<count .spread.decompose byT];

// --- synthetic session: ground truth recovery within 5% tolerance ---
scenario:.spreadSynth.genSession[.z.p-0D02:00:00;3000;1.5];
rec:.spreadSynth.checkRecovery scenario;
.test.assert["synthetic: stressVolMult recovered within tolerance";first exec pass from rec where check=`stressVolMult];
.test.assert["synthetic: richnessBps recovered within tolerance";first exec pass from rec where check=`richnessBps];

// --- .spread.shareByTime: shares sum to 100% per bucket, and volSprd's share is
// higher in the stressed regime than the normal one - same synthetic ground
// truth as the stressVolMult check above, viewed as a share instead of a level ---
shr:.spread.shareByTime[scenario`quotes;`month;enlist`marketStatus];
totals:0!select totalPct:sum pctOfTotal by time,marketStatus from shr;
.test.assert["shareByTime: pctOfTotal sums to 100 per bucket";all 1e-6>abs 100-totals`totalPct];
volShr:0!select from shr where component=`volSprd;
stressedShare:first exec pctOfTotal from volShr where marketStatus=`stressed;
normalShare:first exec pctOfTotal from volShr where marketStatus=`normal;
.test.assert["shareByTime: volSprd's share of totalSprd is higher when stressed";stressedShare>normalShare];

-1 "";
-1 "ALL TESTS PASSED";
exit 0