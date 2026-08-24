// Non-interactive test runner for sre/logToTab.q
//   q test/testLogToTab.q
// Exits 0 with "ALL TESTS PASSED" on success, throws (non-zero exit,
// stack trace on stderr) on the first failing assertion.
//
// Runs single-process via a loopback connection - see scripts/initLogging.q's
// header comment for why that's a fair stand-in for a separate mon process.

system "p 5098";
logs:([] timestamp:`timestamp$(); sym:`symbol$(); level:`symbol$(); host:`symbol$(); pid:`int$(); handle:`int$(); user:`symbol$(); mem:`long$(); code:`symbol$(); message:());
upd:insert;

system "l ./sre/logToTab.q";

.test.assert:{[msg;cond] if[not cond;'"FAILED: ",msg]; -1"PASSED: ",msg;};

// --- reserved-keyword sanity: logToTab.q must not have clobbered the
// built-in `log` function it deliberately avoided reusing as a table name ---
.test.assert["the built-in `log` function still works (table is named `logs`, not `log`)";1e-9>abs 1.0-log exp 1];

// --- .logToTab.write: always records to the local ring buffer, regardless
// of the console threshold - only the printed banner is level-gated ---
before:count .logToTab.tab;
.logToTab.setLevel[`FATAL];  / nothing below FATAL should print...
.logToTab.write[`DEBUG;`TL_D001;"below-threshold message"];
.test.assert["write: ring buffer records a message even when it's below the print threshold";(count .logToTab.tab)=before+1];
.test.assert["write: ring buffer's last row carries the right code despite being below threshold";`TL_D001=exec last code from .logToTab.tab];
.logToTab.setLevel[`INFO];   / restore default for the rest of the run

// --- .logToTab.procName / .connect / .log: a full round trip lands the
// right row, with the right values, in the right columns ---
.logToTab.procName:`testProc;
.logToTab.connect[`::5098];
.test.assert["connect: loopback handle opened (not null)";not null .logToTab.monHandle];

logMsg:.logToTab.log[`WARN;`TL_W001;"round trip test message"];
.test.assert["log: return value carries the level/code/msg that were passed in";(logMsg`level)=`WARN];
.test.assert["log: return value's code matches";(logMsg`code)=`TL_W001];
.test.assert["log: return value's msg matches";(logMsg`msg)~"round trip test message"];

row:-1#0!logs;
.test.assert["log: exactly one row reached the mon `logs` table";1=count logs];
.test.assert["log: sym carries .logToTab.procName";(first row`sym)=`testProc];
.test.assert["log: level column matches";(first row`level)=`WARN];
.test.assert["log: code column matches";(first row`code)=`TL_W001];
.test.assert["log: message column matches";(first row`message)~"round trip test message"];
.test.assert["log: pid column is this process's .z.i";(first row`pid)=.z.i];
.test.assert["log: handle column is .z.w at publish time (0 for a loopback call)";not null first row`handle];
.test.assert["log: mem column is a positive number of MB";(first row`mem)>=0];

// --- forwarding is unconditional: raising the console threshold above a
// message's level still lets it reach `logs` (only the terminal is quieter) ---
.logToTab.setLevel[`ERROR];
.logToTab.log[`INFO;`TL_I001;"quiet on console, loud in `logs"];
.test.assert["log: forwarding ignores the console threshold - the INFO row still landed";2=count logs];
.test.assert["log: the below-threshold row's fields are intact";(exec first message from logs where code=`TL_I001)~"quiet on console, loud in `logs"];
.logToTab.setLevel[`INFO];

// --- lazy reconnect: if .monHandle is null on the next .log call (however
// that happened - a real drop is .z.pc's job to notice, not exercised here
// since a loopback handle is 0 and 0 can't be hclose'd), .log reopens it
// before publishing rather than silently dropping the message ---
.logToTab.monHandle:0Ni;
.logToTab.log[`INFO;`TL_I002;"sent after a simulated disconnect"];
.test.assert["log: lazy reconnect re-opened the handle before publishing";not null .logToTab.monHandle];
.test.assert["log: the post-reconnect row made it to `logs`";3=count logs];
.test.assert["log: the post-reconnect row's fields are intact";(exec first message from logs where code=`TL_I002)~"sent after a simulated disconnect"];

// --- a mon address that was never valid fails without signalling - a
// monitoring outage must never be able to crash the process being monitored.
// Reaching the assert below at all is itself part of the proof: a signal
// here would have aborted the script before this line ran. ---
.logToTab.monAddr:`:localhost:1;  / nothing listens here
.logToTab.monHandle:0Ni;
.logToTab.log[`INFO;`TL_I003;"should not throw"];
.test.assert["log: monHandle stays null after a failed reconnect attempt, and no signal was raised getting here";null .logToTab.monHandle];

-1 "";
-1 "ALL TESTS PASSED";
exit 0
