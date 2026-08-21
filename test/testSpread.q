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
br:.spread.byRegime[toy;`$()];
.test.assert["byRegime: wavg of a single row returns that row's value";
  (1e-9>abs 0.8-exec first refSprd from br where aggression=`low) and
  (1e-9>abs 0.4-exec first volSprd from br where aggression=`high)];

// --- .spread.vsReference: richness recovered exactly for a hand-built pair ---
ref:([]sym:enlist`EURUSD;benchmarkSprd:enlist 1.0);
vr:.spread.vsReference[select from toy where sym=`EURUSD,aggression=`low;ref;enlist`sym;`benchmarkSprd];
.test.assert["vsReference: richnessBps == 1e4*(totalSprd-benchmarkSprd)";1e-6>abs (first vr`richnessBps)-1e4*1.32-1.0];

// --- synthetic session: ground truth recovery within 5% tolerance ---
scenario:.spreadSynth.genSession[.z.p-0D02:00:00;3000;1.5];
rec:.spreadSynth.checkRecovery scenario;
.test.assert["synthetic: stressVolMult recovered within tolerance";first exec pass from rec where check=`stressVolMult];
.test.assert["synthetic: richnessBps recovered within tolerance";first exec pass from rec where check=`richnessBps];

-1 "";
-1 "ALL TESTS PASSED";
exit 0