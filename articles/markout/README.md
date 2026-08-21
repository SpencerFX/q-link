## Running the code for "From Markout to Market Impact"

From the repo root:

```bash
q scripts/initMarkout.q
```

This loads `.util.*`/`.markout.*`/`.impact.*` (`analytics/markOutImpact.q`) and the synthetic
data generator (`data/generator.q`), builds a synthetic 6-hour EURUSD session with five known
impact events baked in, and leaves three globals in the workspace:

- `scenario` — dict of `rate` / `trades` / `orders` / `groundTruth` (the synthetic session)
- `markout` — `.markout.calc` run over `scenario`'s trades against its rate series
- `impact` — recovered temp/perm impact per order compared against the injected ground truth

`impact` lines up the injected ground truth against what `.impact.decompose` recovered, per order:

![q)impact console output](articles/images/impact_table.png)