// sre/logToTab.q
// A leveled logger that, in addition to writing the usual stdout/stderr
// banner line, forwards every message as a row into a remote `logs` table -
// so a fleet of q processes can be grepped/queried from one place instead
// of N separate log files. Self-contained: no dependency on any other file
// in this repo, and no assumption about what's listening on the other end
// beyond "a process with a `logs` table shaped like the one documented
// below, whose root `upd` inserts into it" - the same minimal contract any
// kdb+ tickerplant subscriber already satisfies.
//
// Design is discussed in detail in the companion article:
//   articles/logging/loggingSRE.md
//
// Quick start:
//   system "l ./sre/logToTab.q";
//   .logToTab.procName:`myProcess;              / tags every row - see below
//   .logToTab.connect[`:host:port];              / a process hosting `logs`
//   .logToTab.log[`WARN;`MY_W001;"message text"];
//
// `logs` table shape (timestamp first, to match how q sorts/partitions
// time-series data; not named `log` - see the reserved-keyword note below):
//   logs:([] timestamp:`timestamp$(); sym:`symbol$(); level:`symbol$();
//             host:`symbol$(); pid:`int$(); handle:`int$(); user:`symbol$();
//             mem:`long$(); code:`symbol$(); message:());
// `sym` carries `.logToTab.procName - the same column a tick would use for
// an instrument, here identifying which process a log line came from.
.logToTab.info.loaded:0b;

//The five standard levels (highest severity first), per the usual FATAL
//down to DEBUG convention - see the article for when to use which.
.logToTab.levels:`FATAL`ERROR`WARN`INFO`DEBUG!0 1 2 3 4;

//Active threshold: messages at a level with a HIGHER index than this are
//written locally but not (by default) worth shipping anywhere expensive -
//callers may still choose to log below this and rely on .logToTab.tab alone.
.logToTab.level:.logToTab.levels`INFO;

//This process's identity, stamped into every forwarded row's `sym` column -
//set this once near the top of your script, before the first .log call.
.logToTab.procName:`unknown;

//Local ring buffer - every message logged locally, independent of whether
//forwarding is connected/configured. Cheap insurance: if the mon process
//is down, you still have this process's own recent history in memory.
.logToTab.tab:([] time:`timestamp$(); level:`symbol$(); code:`symbol$(); msg:());
.logToTab.tabMax:10000;

//Handle to the remote `logs`-hosting process, 0Ni if not connected
.logToTab.monHandle:0Ni;

//Address last passed to .connect, ` if never called - re-tried lazily,
//on the next .log call, if the connection has dropped. See the article's
//"why lazy, not a timer" section for why this doesn't claim .z.ts.
.logToTab.monAddr:`;

//@func   | .logToTab.setLevel
//@param  | level | -11 -7 | symbol name (e.g. `DEBUG) or its numeric rank
//@desc
//Sets the active local threshold - messages below it are dropped before
//formatting, the same idea as core/utils/log.q's setLogLevel in the
//companion openQ repo
//@desc
.logToTab.setLevel:{[level]
 if[-11h~type level;:.logToTab.level:.logToTab.levels level];
 .logToTab.level:level;
 };

//@func   | .logToTab.mem
//@return | -7 | This process's current heap usage, in MB
//@desc
//Same formula core/utils/log.q uses, so numbers are comparable across processes
//@desc
.logToTab.mem:{[] `long$floor (.Q.w[]`used)%1024*1024};

//@func   | .logToTab.write
//@param  | level | -11 | symbol log level
//@param  | code  | -11 | symbol code
//@param  | msg   | 10  | string log message
//@return | 99 | The dict actually written (time/level/code/msg)
//@desc
//Formats and writes one banner line to stdout (INFO/DEBUG) or stderr
//(WARN and above) if it passes the level threshold, and always records it
//into the local ring buffer regardless of the threshold - the buffer is
//meant to answer "what just happened here", not "what's worth escalating"
//@desc
.logToTab.write:{[level;code;msg]
 t:.z.p;
 if[.logToTab.level>=.logToTab.levels level;
    line:"|" sv (_[-3;string t];string .logToTab.procName;string level;string .logToTab.mem[];string code;msg);
    $[.logToTab.levels[`WARN]>=.logToTab.levels level;-2;-1] line
   ];
 `.logToTab.tab insert (t;level;code;msg);
 if[.logToTab.tabMax<count .logToTab.tab;.logToTab.tab:.logToTab.tabMax#.logToTab.tab];
 `time`level`code`msg!(t;level;code;msg)
 };

//@func   | .logToTab.connect
//@param  | address | -11 | `:host:port (or `::port for a loopback) of the mon process
//@return | -6 | Handle opened, or 0Ni on failure
//@desc
//Opens (or reopens) the connection to the process hosting `logs`. Failure
//is logged locally, not signalled - a monitoring outage should never be
//the thing that crashes the process being monitored.
//@desc
.logToTab.connect:{[address]
 .logToTab.monAddr:address;
 .logToTab.monHandle:@[hopen;address;{[a;e].logToTab.write[`WARN;`LT_W001;"Failed to connect to mon process ",(string a)," with: ",e];0Ni}[address]];
 };

//@func   | .logToTab.row
//@param  | logMsg | 99 | The dict returned by .logToTab.write (time/level/code/msg)
//@return | 0 | A flat value tuple in `logs`' column order (timestamp,sym,level,host,pid,handle,user,mem,code,message)
//@desc
//Adds the process/host/handle/user context a single process's own log line
//doesn't carry. Returned as a flat tuple, not a dict - see .log's header
//comment for why that shape is the one that reliably round-trips through
//a plain `upd:insert` on the far end.
//@desc
.logToTab.row:{[logMsg]
 (logMsg`time;.logToTab.procName;logMsg`level;`$string .z.h;.z.i;.z.w;`$string .z.u;.logToTab.mem[];logMsg`code;logMsg`msg)
 };

//@func   | .logToTab.log
//@param  | level | -11 | symbol log level (FATAL/ERROR/WARN/INFO/DEBUG)
//@param  | code  | -11 | symbol code
//@param  | msg   | 10  | string log message
//@return | 99 | The dict from .logToTab.write
//@desc
//Writes locally via .logToTab.write (unchanged whether or not forwarding
//is configured), then - if a mon address has ever been given - makes sure
//the connection is up (lazy reconnect, see .connect) and async-publishes
//the same message as one row into its `logs` table. A process that never
//calls .connect behaves exactly as if this file only had .write in it.
//
//Sent as (`upd;`logs;row) with row a flat value tuple, not a dict: this is
//the classic single-row kdb+ tick.q feed handler convention
//(neg[h](`upd;`tab;data)) - a plain `upd:insert` on the receiving end
//accepts it directly, with no schema-aware conversion needed on either side.
//@desc
.logToTab.log:{[level;code;msg]
 logMsg:.logToTab.write[level;code;msg];
 if[and[null .logToTab.monHandle;not .logToTab.monAddr~`];.logToTab.connect[.logToTab.monAddr]];
 if[not null .logToTab.monHandle;
    row:.logToTab.row logMsg;
    @[{[h;msg]neg[h]msg}[.logToTab.monHandle;];(`upd;`logs;row);{[e].logToTab.monHandle:0Ni; .logToTab.write[`WARN;`LT_W002;"Failed to publish log row to mon process, will retry next call: ",e]}]
   ];
 logMsg
 };

.logToTab.info.loaded:1b;
