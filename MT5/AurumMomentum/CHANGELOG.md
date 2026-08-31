# AurumMomentum — Changelog

## v1.30 — 2026-07-07
- Time exit generalized (step 3a): `InpHoldBars` (default 1) — each position closes after that many candles instead of always at the next one. Up to `InpHoldBars` positions can be open at once (one per candle).
- `InpMinBodyATR` default reverted to 0: the v1.20 backtests showed the body filter selects candles that mean-revert (EP worsened on all timeframes).

## v1.20 — 2026-07-06
- Momentum entry filter (step 2): only trade candles whose body ≥ `InpMinBodyATR` × ATR(`InpATRPeriod`) of the closed bar. Defaults: 0.5 × ATR(14); `InpMinBodyATR=0` disables. Exit logic unchanged from v1.10.

## v1.10 — 2026-07-06
- New exit mode `InpExitMode` (default 1): close every position at the following bar close — the continuation bet resolves in one candle. Mode 0 keeps the v1.01 basket-target behaviour.
- Step 1 of the one-change-at-a-time experiment plan: isolate the exit change; entry logic untouched (one order per closed candle, no filters).

## v1.01 — 2026-07-06
- Basket exit: when total floating profit (incl. swap) of all EA positions reaches `max(buys, sells) × InpProfitPerOp`, all positions of both directions are closed. E.g. 2 buys + 1 sell → target 2 × $1.00 = $2.00.
- New input `InpProfitPerOp` (default 1.00, account currency; 0 = off). Checked on every tick.

## v1.00 — 2026-07-06
- Initial release: on every closed candle opens one market order in the candle's direction (bullish close → buy, bearish close → sell). Doji candles skipped.
- Hedging-friendly: buys and sells can be open simultaneously. No exit logic — positions stay open until closed manually or by optional SL/TP.
- Inputs: `InpLots` (default 0.01), `InpSLPoints` / `InpTPPoints` in points (0 = off), `InpMagic` (20260706).
- Lot is clamped to broker volume min/max/step (e.g. RoboForex ProCent min 0.1).
