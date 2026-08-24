//====================================================================
// Performance report: sre/logToTab.q — timed against a live (loopback)
// mon connection, the same way it would run in production.
//
//   q perf/perfLogToTab.q
//
// See perf/perfChk.q for the shared timing harness and methodology.
//====================================================================

system "p 5097";
logs:([] timestamp:`timestamp$(); sym:`symbol$(); level:`symbol$(); host:`symbol$(); pid:`int$(); handle:`int$(); user:`symbol$(); mem:`long$(); code:`symbol$(); message:());
upd:insert;

system "l ./sre/logToTab.q";
system "l ./perf/perfChk.q";

.logToTab.procName:`perfProc;
.logToTab.connect[`::5097];

//--------------------------------------------------------------------
// Benchmark data
//--------------------------------------------------------------------
.perf.data.logMsg:.logToTab.write[`INFO;`PF_I001;"benchmark message"];

//Console printing (stdout/stderr I/O) is a real cost but not what these
//numbers are meant to isolate - the table-write/publish cost itself is.
//Raise the threshold above every level used below so nothing prints
//during the timed runs; .logToTab.tab still records everything either way.
.logToTab.setLevel[`FATAL];

//====================================================================
// sre/logToTab.q
//====================================================================
.perf.priv.run[`logToTab;`mem;5000;"(.logToTab.mem[])"];
.perf.priv.run[`logToTab;`row;5000;"(.logToTab.row .perf.data.logMsg)"];
.perf.priv.run[`logToTab;`write.local_only;2000;"(.logToTab.write[`INFO;`PF_I002;\"local-only write\"])"];
.perf.priv.run[`logToTab;`log.connected;2000;"(.logToTab.log[`INFO;`PF_I003;\"connected round trip\"])"];

//--------------------------------------------------------------------
// log.disconnected: same call, but with monAddr unset - the "library
// wasn't wired up to a mon process at all" steady-state cost, not the
// one-time-per-drop reconnect-attempt cost (that path is exercised and
// asserted, not timed, in test/testLogToTab.q - the OS's connection-
// refused delay dominates it and would swamp every other number here)
//--------------------------------------------------------------------
.logToTab.monAddr:`;
.logToTab.monHandle:0Ni;
.perf.priv.run[`logToTab;`log.disconnected;2000;"(.logToTab.log[`INFO;`PF_I004;\"unconfigured write\"])"];

//====================================================================
// Report
//====================================================================
-1 "";
-1 "Dataset sizes: logs=",(string count logs)," ring buffer=",string count .logToTab.tab;
-1 "";
.perf.report[];
exit 0
