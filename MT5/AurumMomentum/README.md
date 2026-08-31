# AurumMomentum

**Platform:** MetaTrader 5  
**Version:** 1.30  
**Last updated:** 2026-07-07  

## What it does

Simple candle-direction momentum EA for **any symbol and timeframe**. On every closed candle, it opens one market order in the candle's direction — bullish close → buy, bearish close → sell. Doji candles (open = close) are skipped. A hedging account is assumed, so buys and sells can coexist.

Designed as a research and exploration EA: deliberately minimal, with one-change-at-a-time additions to isolate the effect of each modification.

## Exit modes

| Mode | `InpExitMode` | Behaviour |
|---|---|---|
| Time exit | 1 (default) | Close each position after `InpHoldBars` candles — the continuation bet resolves in N bars |
| Basket target | 0 | Close all positions when total floating profit ≥ `max(buys, sells) × InpProfitPerOp` |

## Optional filter

**ATR body filter** (`InpMinBodyATR`): only trade candles with a body ≥ `InpMinBodyATR × ATR(InpATRPeriod)`. Set to 0 (default) to disable — backtests showed the filter selects mean-reverting candles and worsens performance.

## Configuration

| Input | Default | Description |
|---|---|---|
| `InpLots` | 0.01 | Lot size per order |
| `InpSLPoints` | 0 | Stop loss in points (0 = none) |
| `InpTPPoints` | 0 | Take profit in points (0 = none) |
| `InpExitMode` | 1 | Exit: 0 = basket target, 1 = time exit |
| `InpHoldBars` | 1 | Mode 1: close position after this many candles |
| `InpMinBodyATR` | 0.0 | Min candle body as a multiple of ATR (0 = off) |
| `InpATRPeriod` | 14 | ATR period for the body filter |
| `InpProfitPerOp` | 1.00 | Mode 0: basket profit target per operation (0 = off) |
| `InpMagic` | 20260706 | Magic number |

See [CHANGELOG.md](CHANGELOG.md) for version history.
