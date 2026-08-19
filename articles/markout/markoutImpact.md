# From Markout to Market Impact

## Summary

Markout and Market Impact are often viewed hand-in-hand and are central to post-trade analytics. In the context of this article and the code, we categorise them in the following way:

- **Markout asks:** after a client's trade executes, did the market keep moving in the direction they traded? It's a measure of who benefited from the timing of a fill — useful for client tiering, venue comparison, and understanding the real cost of internalising flow.

- **Market impact asks:** something narrower and more mechanical: when your own order hits the market, how much does it move the price, and does that move stick or fade? It's a measure of your own execution footprint — useful for tuning algo aggression, sizing orders, and understanding the true cost of demanding liquidity right now versus waiting.

---

## Repo

The code discussed in this article can be found at:

https://github.com/SpencerFX/q-link

To load the functions, test data, and run the pipeline from within the `q-Link` directory:

```bash
q ./scripts/initMarkout.q