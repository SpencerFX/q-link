## Running the code for "Explaining the Spread"

From the repo root:

```bash
q scripts/initSpread.q
```

This loads `.spread.*` (`analytics/spread.q`) and the synthetic quote generator
(`data/spreadGenerator.q`), builds a synthetic 6,000-quote session across 3 symbols, 3
aggression levels, and a `normal`→`stressed` regime shift with known effects baked in,
and leaves four globals in the workspace:

- `scenario` — dict of `quotes` / `benchmark` / `groundTruth` (the synthetic session)
- `recovery` — `.spread.byRegime` / `.spread.vsReference` output checked against the
  injected ground truth (stress-volatility multiplier, benchmark richness)
- `byRegime` — spread build-up weight-averaged by aggression × market status
- `byTime` — spread build-up weight-averaged by minute, independent of `byRegime`'s check

To run the same checks as hard pass/fail assertions instead (suitable for CI):

```bash
q test/testSpread.q
```

`recovery` lines up the injected ground truth against what `.spread.byRegime` and
`.spread.vsReference` recovered:

```
q)recovery
check         expected recovered relErrPct  pass
------------------------------------------------
stressVolMult 4        4.004076  0.101891   1
richnessBps   500      500.2515  0.05029823 1
```

![Same quote, priced two ways](articles/spread/images/composition.png)
