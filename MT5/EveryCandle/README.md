# EveryCandle

**Platform:** MetaTrader 5  
**Version:** (no version tag)  
**Last updated:** 2026-02-10

## What it does

Minimal candle-momentum EA. At the open of every new candle it reads the direction of the **previous** candle and immediately enters a trade in that direction. The position is closed automatically when the candle from the same timeframe closes **in profit**.

## Logic

```
New candle detected on current TF
        │
        ├─ Previous candle was bullish (close > open)?
        │     → BUY at market, SL = previous candle Low
        │
        └─ Previous candle was bearish?
              → SELL at market, SL = previous candle High
```

**Position management (per originating timeframe):**  
Every tick, for each open position, the EA checks whether the candle of the **timeframe that spawned the trade** has closed. If that candle closed and the position is in profit → close the position.

No take-profit level is set; the exit is purely event-driven on candle close.

## Multi-timeframe support

The EA uses `PeriodSeconds(_Period)` as the magic number. This means:
- Each timeframe has a unique magic number.
- Running the EA on multiple chart windows simultaneously creates independent trade lifecycles per timeframe.
- The management loop iterates all open positions and resolves each by its own originating timeframe.

## Parameters

None — lot size is hard-coded at 0.1. All other behaviour is derived from the chart's current timeframe.

## Notes

- Works best in trending markets with clear directional candles.
- No take-profit means the trade stays open until the originating candle closes, which can be a long time on higher timeframes.
- Does not compound or add positions — one trade per timeframe at a time.
