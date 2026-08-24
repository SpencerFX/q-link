// scripts/initLogging.q
// Entry point for sre/logToTab.q. Runs single-process: this script opens
// its own listening port and has logToTab.q connect back to it over a
// loopback handle, standing in for what would normally be a second,
// separate q process hosting the `logs` table (see articles/logging/
// loggingSRE.md for why a loopback is a fair stand-in - the wire protocol
// doesn't know or care that the two ends happen to be the same process).
//
//   q scripts/initLogging.q
//
// Simulates a small, realistic operational scenario for a pricing service
// (the kind of process markout/spread from the other two articles would
// run inside) - connect, a lagging feed, an error, recovery - at a mix of
// levels, then raises the console threshold to demonstrate that raising it
// only quiets the terminal, not what lands in `logs`.
// `logs` and `upd` are set at true top level, not inside init[] below -
// `upd::insert` from inside a lambda signals 'upd (kdb+ treats a global
// named upd specially for its own IPC message dispatch); the classic
// top-level `upd:insert` tickerplant-subscriber idiom is unaffected.
system "p 5099";
logs:([] timestamp:`timestamp$(); sym:`symbol$(); level:`symbol$(); host:`symbol$(); pid:`int$(); handle:`int$(); user:`symbol$(); mem:`long$(); code:`symbol$(); message:());
upd:insert;

init:{[]
    system "l ./sre/logToTab.q";
    .logToTab.procName:`pricingSvc;
    .logToTab.connect[`::5099];

    .logToTab.log[`INFO;`PS_I001;"connected to rate feed EURUSD"];
    .logToTab.log[`DEBUG;`PS_D001;"received 1,204 rate ticks in the last second"];  / below default INFO threshold - see console vs. logs below
    .logToTab.log[`WARN;`PS_W001;"rate feed lagging 850ms behind wall clock, buffering"];
    .logToTab.log[`ERROR;`PS_E001;"quote for EURUSD rejected: rate is 3200ms stale"];
    .logToTab.log[`INFO;`PS_I002;"rate feed caught up, quoting resumed"];

    -1 "";
    -1 "--- raising console threshold to WARN (forwarding is unaffected) ---";
    .logToTab.setLevel[`WARN];
    .logToTab.log[`INFO;`PS_I003;"this INFO line won't print, but it's still in `logs` and `.logToTab.tab"];

    logsSnapshot::0!logs;
    ringSnapshot::0!.logToTab.tab;
 };

init[];

-1 "";
-1 "globals left in the workspace: logs, logsSnapshot, ringSnapshot";
-1 "log count (mon table): ",string count logs;
-1 "log count (local ring buffer): ",string count .logToTab.tab;
