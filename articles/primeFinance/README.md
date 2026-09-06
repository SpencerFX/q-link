## About "A Locate Isn't a Number — It's a Reservation"

Unlike this repo's other articles, there's no `q` script to run here —
`primeFinance` is a module of [openQ](https://github.com/SpencerFX/openQ),
the author's kdb+ trading platform, under
`modules/analytics/primeFinance/`. This piece documents its design: a
scored, constrained locate-allocation algorithm (not a plain sum of
available shares); a lender reference table deliberately built as a plain
join instead of a true kdb+ foreign key, so a legitimate borrow from an
as-yet-unseeded lender degrades to nulls instead of a hard error; and fee
calibration/position risk marked against real historical equity data
(`eq_d1_yfinance`/`eq_m1_yfinance`) rather than synthetic prices.

Every number quoted in the article came from a real, live
`primefinance_tp`/`primefinance_cep` — most of it from one clean run of
`modules/analytics/primeFinance/simulator.q`, including one place where the
simulator's own code comment turned out to be stale (checked and reported
honestly rather than repeated), and a couple of pieces (a real duplicate
buy-in-alert finding, and the crowding table) from reconnecting to that
same CEP later and querying its live state directly, by then carrying a
different, larger book this article didn't seed. The article's own Known
limitations section says exactly which numbers came from which session,
rather than treating every claim as equally attributable to one run.

Read the article: [`primeFinance.md`](primeFinance.md).
