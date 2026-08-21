//====================================================================
// RDB — subscribes to the tickerplant, keeps today's ticks in memory.
//
//   q analytics/core/rdb.q             (listens on 5011, tp on 5010)
//   q analytics/core/rdb.q -p 5012     (override rdb's own port)
//
// Set .rdb.tpPort before loading (or edit below) to point at a
// tickerplant on a non-default port.
//====================================================================
\p 5011

.rdb.tpPort:5010;
.rdb.tp:hopen .rdb.tpPort;

//--------------------------------------------------------------------
// Subscribe to every table tp knows about; .tp.sub returns the empty
// schema for each, which becomes this process's actual in-memory
// table - so rdb never hardcodes tp's schemas, it just mirrors them.
//--------------------------------------------------------------------
.rdb.schemas:.rdb.tp(`.tp.sub;`);
.rdb.tables:key .rdb.schemas;
{x set y}'[.rdb.tables;value .rdb.schemas];

//@func | upd
//@param | t | -11 | table name
//@param | data | 99 | unkeyed table of new rows, columns matching t's schema
//@desc  called (async) by tp for every republished update; appends to
// the matching in-memory table, keyed by table NAME (the standard
// tick.q idiom - `t insert data` where t is a symbol appends to the
// global table that symbol names).
//@desc
upd:{[t;data] t insert data};

//@func | .rdb.status
//@desc  row counts for every subscribed table, for a quick sanity check.
.rdb.status:{[] .rdb.tables!count each value each .rdb.tables};

//@func | .rdb.eod
//@param | d | -14 | trade date to save under, date atom (defaults to .z.D if not given)
//@desc
// splay every in-memory table to analytics/core/hdb/<date>/<table>/,
// symbol-enumerated against the hdb's sym file via .Q.en - the
// standard end-of-day rdb->hdb write. Doesn't clear the in-memory
// tables afterward (left as a deliberate call the operator makes
// separately, rather than something eod does implicitly).
//@desc
.rdb.eod:{[d]
  d:$[0=count d;.z.D;d];
  hdbDir:`:analytics/core/hdb;
  {[hdbDir;d;t]
    dir:` sv hdbDir,`$(string d;string t);
    dir set value t;
    -1 "rdb: saved ",(string t)," (",(string count value t)," rows) to ",string dir;
   }[hdbDir;d] each .rdb.tables;
 };

-1 "rdb: subscribed to ",(", " sv string .rdb.tables),", listening on port ",string system"p";
