# AurumSweep

**Platform:** MetaTrader 5  
**Version:** 1.06  
**Last updated:** 2026-07-05  

## What it does

Prop-challenge EA for **XAUUSD M5**, tuned for FundedNext Stellar 1-Step ($25k: 10% target, 3% daily / 6% max static drawdown). Implements the Smart Money Concepts (SMC) playbook: detect a liquidity sweep or deep pullback, wait for a displacement FVG in the reversal/continuation direction, and enter a limit order at the FVG midpoint.

The default mode (`InpMode = 1`) is **trend-continuation** — after backtesting showed sweep-reversal alone was structurally against gold's 2024–2026 bull regime (PF 0.71–0.80, fading breakouts in a monster trend). Continuation fires on deep pullbacks against a strict H1 bias and uses the same FVG confirmation engine as sweeps.

## Entry logic

1. **H1 swing-structure bias** — fractal 2-2 swings, break confirmed by close. +1 = bullish, −1 = bearish, 0 = neutral.
2. **Sweep detection** (`InpMode 0 / 2`): a closed M5 bar pierces PDH/PDL or the Asian session range (00–07 local) and closes back inside → setup armed.
3. **Pullback detection** (`InpMode 1 / 2`): price retraces ≥ `InpPullbackAtr × ATR M15` from the rolling `InpSwingBars` M5 extreme in the bias direction.
4. **Confirmation**: displacement FVG must appear within `InpConfirmBars` bars of the trigger.
5. **Entry**: limit order at FVG midpoint (or edge), SL beyond the sweep/pullback extreme + ATR buffer, TP at `RR × SL distance` (fixed) or ATR chandelier trail.

## Challenge guards

| Guard | Trigger | Effect |
|---|---|---|
| Daily halt | Day loss ≥ `InpDailyHaltPct`% of initial balance | Close all + halt for the day |
| Max loss guard | Equity ≤ initial × (1 − `InpMaxHaltPct` / 100) | Permanent halt via GlobalVariable `ASW_HALT_<login>` |
| Target lock | Equity ≥ initial × (1 + `InpTargetLockPct` / 100) | Close all + stop forever (challenge passed) |
| Max trades/day | `InpMaxTradesPerDay` entries reached | No new entries until next day |
| Friday cutoff | `InpFriCutH` local hour on Friday | Close all positions; flat over weekend |

## Risk sizing

`InpDynamicRisk = true` (default): risk per trade = `InpCushionFrac (0.20) × cushion above max-loss floor`, capped at `InpRiskPct (1.25%)`. Position size shrinks toward zero as drawdown approaches the halt level, so the account survives bad regimes instead of busting.

## Configuration

| Input | Default | Description |
|---|---|---|
| `InpRiskPct` | 1.25 | Risk per trade cap (% of balance) |
| `InpDynamicRisk` | true | Scale risk to remaining drawdown cushion |
| `InpCushionFrac` | 0.20 | Fraction of cushion used as risk budget |
| `InpRR` | 2.5 | Reward:risk ratio (fixed TP mode) |
| `InpExitMode` | 1 | 0 = fixed TP at RR, 1 = ATR chandelier trail |
| `InpTrailAtr` | 2.0 | Trail distance (× ATR M15) |
| `InpBreakEvenAtR` | 1.0 | Activate trail / BE move at +N×R (0 = off) |
| `InpInitialBalance` | 0.0 | Challenge starting balance (0 = balance at first run) |
| `InpDailyHaltPct` | 2.4 | Daily loss halt (% of initial balance) |
| `InpMaxHaltPct` | 5.0 | Permanent max-loss halt (% of initial balance) |
| `InpTargetLockPct` | 10.2 | Profit lock trigger (% of initial balance) |
| `InpMaxTradesPerDay` | 4 | Max entries per day |
| `InpServerOffset` | 3 | Broker server UTC offset (hours) |
| `InpLocalOffset` | 1 | Local UTC offset (hours) |
| `InpMode` | 1 | 0 = sweep-reversal, 1 = trend-continuation, 2 = both |
| `InpBiasMode` | 1 | 0 = off, 1 = soft (allow neutral), 2 = strict |
| `InpConfirmBars` | 9 | Bars after trigger to find FVG confirmation |
| `InpOrderExpiryBars` | 18 | Pending order lifetime (M5 bars) |
| `InpMinFvgAtr` | 0.10 | Min FVG gap size (× ATR M15) |
| `InpSLBufAtr` | 0.50 | SL buffer beyond sweep/pullback extreme (× ATR M15) |
| `InpNewsFilter` | true | Block entries −60 min / +15 min around USD news |
| `InpLogDB` | true | SQLite logging to `MQL5\Files\AurumSweep.db` |

## Activity logging (SQLite)

When running live, the EA writes to `MQL5\Files\AurumSweep.db`:

| Table | Contents |
|---|---|
| `trades` | Setup type, direction, sweep time, fill/close time, entry/SL/TP, lots, P&L, result |
| `events` | Guard trips and key state changes with timestamp |

## External files required

| File | Location | Purpose |
|---|---|---|
| `fvg_news.csv` | `%APPDATA%\MetaQuotes\Terminal\Common\Files\` | News calendar (auto-synced live by AurumBlock) |

See [CHANGELOG.md](CHANGELOG.md) for version history.
