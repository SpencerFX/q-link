//====================================================================
// Shared performance-check harness — functions only, no article
// knowledge. Per-article runners (perf/perfMarkOut.q, perf/perfSpread.q)
// load this, load their own analytics + generator files, build their
// own .perf.data.*, call .perf.priv.run per function, then .perf.report[].
//
// Methodology: each pure/batch function is timed via `system"ts do[n;expr]"`
// (kdb+'s built-in time+space profiler, called programmatically so the
// (ms;bytes) pair can be captured and tabulated rather than only printed)
// and averaged over n reps. Stateful "real-time path" functions
// (onTrade/onRate/onOrder/onBook/onQuote/sweepPending) are NOT safe to
// naively loop: onRate/onBook DRAIN their pending table on a match, so a
// second identical call measures an empty-hits no-op rather than the
// real cost. A runner should benchmark those as a single realistic bulk
// call instead (seed N distinct pending rows, then time one tick that
// completes/evicts all of them at once).
//====================================================================

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

//@func | .perf.report
//@desc  print the accumulated .perf.results, console widened first so
// the table isn't row/column-truncated.
.perf.report:{[]
  system "c 60 240";
  show .perf.results;
  };

//@func | .perf.priv.seedPending
//@desc  reset `pendingTab` (a symbol naming a global keyed table, e.g.
// `` `.markout.pending``) to empty, then call `onFn` once per row built
// by `rowFn` (a unary function of x:0..n-1 returning the dict `onFn`
// expects) over `til n` - the "seed n distinct pending entities" step
// shared by every onRate/onBook/sweepPending bulk-drain benchmark.
.perf.priv.seedPending:{[pendingTab;onFn;n;rowFn]
  pendingTab set 0#value pendingTab;
  onFn each rowFn each til n;
  };
