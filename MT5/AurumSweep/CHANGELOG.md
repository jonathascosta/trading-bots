# AurumSweep — Changelog

## v1.06 — 2026-07-05

Defaults aligned with the walk-forward-validated configuration, so attaching the EA
with default inputs equals the release-candidate setup. No logic changes.

- `InpExitMode` 0 → 1 (ATR trail), `InpTrailAtr` 1.0 → 2.0
- `InpPullbackAtr` 1.5 → 2.25, `InpSwingBars` 36 → 48
- `InpDailyHaltPct` 2.0 → 2.4, `InpMaxTradesPerDay` 3 → 4

## v1.05 — 2026-07-05

Dynamic risk sizing (never-bust challenge mode). Challenge sims on 2026 real ticks
(fixed 1.25% risk, guards on) showed 1 pass in 3 start months: Feb passed +10.3% in
11 trading days; Jan and Mar busted at the -5% permanent halt (Jan busted even at
0.75%). Since the 1-Step has no time limit, busting is never optimal.

- `InpDynamicRisk` (default true): risk per trade = `InpCushionFrac` (0.20) x the
  equity cushion above the max-loss floor, capped at `InpRiskPct` (now 1.25%).
  Size shrinks toward zero as drawdown approaches the halt level - the account
  survives bad regimes and waits them out instead of busting.

## v1.04 — 2026-07-05

ATR trailing exit. Walk-forward 2026 of the validated config (pass 118: RR 2.5,
BE 1.0R, pull 2.25, swing 48, confirm 9) held PF 1.14 / 147 trades / +8.6% in 6 months,
but avg win was only 1.22R — the 1R break-even move caps runners.

- `InpExitMode`: 0 = fixed TP at RR (default, unchanged), 1 = chandelier ATR trail
  (no TP; SL ratchets at `InpTrailAtr` x ATR M15 once +`InpBreakEvenAtR` x R is reached)
- `InpRR` default 2.0 → 2.5 (walk-forward validated value)
- DB result tag "trail" for profitable stop-outs

## v1.03 — 2026-07-05

Trend-continuation mode. Raw-edge baseline 2024–2026 (72 trades, guards off) showed
sweep-reversal is structurally against the regime (gold 2040 → 4700): 33% win at RR 2,
PF 0.71–0.80. Fading breakouts in a monster bull loses on both sides.

- `InpMode`: 0 = sweep-reversal, 1 = trend-continuation (default), 2 = both
- Continuation trigger: pullback ≥ `InpPullbackAtr` (1.5) × ATR M15 from the rolling
  `InpSwingBars` (36) M5 extreme, in the direction of a strict H1 bias
- Same displacement-FVG confirmation and entry/SL/TP engine as sweeps; the SL anchor
  follows the deepest pullback point while waiting for confirmation

## v1.02 — 2026-07-04

Volatility-scaled distances. v1.01 backtest (8 trades, 0 TP hits, PF 0.02) showed
fixed-pip stops are miscalibrated for gold at $4-5k: 20-25 pip SLs sit inside
single-bar M5 noise (min holding time was 11 s).

- SL buffer / min SL / max SL / min FVG now expressed as multiples of ATR(14) M15:
  `InpSLBufAtr=0.5`, `InpMinSLAtr=1.0`, `InpMaxSLAtr=4.0`, `InpMinFvgAtr=0.10`
  (replaces the fixed-pip inputs)
- Break-even move default 1.0R → 1.5R (BE at 1R was scratching would-be winners)
- ATR handle created in OnInit, released in OnDeinit, cached per M5 bar

## v1.01 — 2026-07-04

Funnel fixes after first 6-month backtest (Jan–Jun 2026, real ticks: only 4 trades,
33 setups → 21 died waiting for FVG, 4 of 8 orders expired unfilled):

- Sweep flags now burn only when a setup is actually armed — sweeps that happen while
  entries are blocked (window/news/bias) no longer kill the level for the whole day
- Confirmation window 6 → 9 bars
- Min FVG gap 5 → 3 pips
- Pending order expiry 12 → 18 bars
- Min SL distance 25 → 20 pips
- NY window extended to 17:30 local

## v1.00 — 2026-07-04

Initial release. Prop-challenge EA for XAUUSD M5, tuned for FundedNext Stellar 1-Step
($25k: 10% target, 3% daily / 6% max static drawdown, min 2 trading days).

**Strategy (SMC / LuxAlgo Price Action Concepts ported to MQL5):**
- H1 swing-structure bias (fractal 2-2 swings, break by close → BOS/CHoCH state)
- Liquidity sweep detection on closed M5 bar: PDH/PDL and Asian range (00–07 local) high/low
- Confirmation: displacement FVG in the reversal direction within N bars after the sweep
- Limit entry at FVG midpoint (or edge), SL beyond sweep extreme + buffer, TP at fixed RR
- Single position; pending order expires after N bars and is invalidated if price
  trades through the SL level before fill

**Risk & challenge guards:**
- Fixed fractional sizing (default 1% risk, RR 2.0), break-even move at +1R
- Daily loss guard: close all + halt for the day at −2% of initial balance
- Max loss guard: permanent halt at −5% (persisted via GlobalVariable across restarts)
- Profit lock: close all + stop forever at +10.2% (challenge passed)
- Max 3 entries/day, Friday cutoff (flat over weekend), spread guard
- News filter reuses `Common\Files\fvg_news.csv` (fed by AurumBlock live sync),
  single zone −60 min → +15 min

**Logging:** SQLite `MQL5\Files\AurumSweep.db` — tables `trades` (setup, entry, result) and `events` (guard trips).

**Notes:**
- Server/local UTC offsets are inputs (FundedNext server offset may differ from Vantage).
- PDH/PDL read from D1 bars (server-day aligned, ~2 h off the local day; acceptable for v1).
