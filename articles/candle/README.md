## About "A Hammer and a Hanging Man Are the Same Candle"

Unlike this repo's other articles, there's no `q` script to run here —
`candle` is a module of [openQ](https://github.com/SpencerFX/openQ), the
author's kdb+ trading platform, under `modules/analytics/candle/`, used
by `modules/backtest/backtest.q` as one of four pluggable alpha models.
This piece documents a 32-pattern, TA-Lib-style candlestick library
ported into it from a third-party q project — the design insight that
some patterns are the same candle shape read two opposite ways depending
on the trend before it, the eleven categories of build-specific bugs
found porting the upstream project to this q build, and a source of
direct inspiration: a Python/TA-Lib blog post
([dataintellect.com](https://dataintellect.com/blog/identifying-japanese-candle-sticks-using-python/))
that demonstrated the same kind of pattern check against the real 2020
COVID crash.

Every number in the article's verification, frequency, and edge-test
sections came from real, live queries against openQ's own `eq_hdb` this
session — real daily bars for AAPL and five more major tech names (MSFT,
GOOGL, AMZN, NVDA, TSLA) for the crash-window comparisons, and all 14
major tech names' full available history (57,911 real bars, 87,301 real
pattern fires) for the large-sample forward-return test — not synthetic
data anywhere. That wider check is what keeps the piece honest: AAPL's
hammer landing exactly on the real 2020 COVID low turns out to be the
exception among six comparable names, not the rule; a genuine,
previously undocumented gap found in `.candle.kicking` (consistently
68–74% of real fires across all six names have no actual price gap)
turns out to generalize rather than being an AAPL artifact; and pushed
to its largest scale — the library's full directional vocabulary against
full real history — not one of 105 pattern/side/horizon comparisons
survives correction for the number of comparisons run. None of these
results are fixed or softened in the piece, consistent with this repo's
practice of reporting a finding honestly rather than quietly patching it
mid-article.

Read the article: [`candle.md`](candle.md).
