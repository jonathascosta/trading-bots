# Anti6MA

**Platform:** MetaTrader 4  
**Version:** 3.2  
**Last updated:** 2025-04-16

## What it does

Counter-trend martingale EA. It trades **against** a 6-period Simple Moving Average — selling when the MA is rising (expecting a pullback) and buying when the MA is falling. If the market keeps moving against the position, it doubles the lot and re-enters at every `ReentryPips` interval.

## Strategy logic

| MA direction | Action |
|---|---|
| Rising | Open SELL |
| Falling | Open BUY |

- **Initial lot** scales with account balance: `floor(balance / 100,000) × 0.1`, minimum 0.1.
- **Re-entry (martingale):** when price moves `ReentryPips` further against the last entry, a new order is opened with twice the previous lot.
- **Exit:** all orders are closed when the aggregate pip profit (lot-weighted) reaches `ExitProfitPips`. The target is dynamically reduced as the grid multiplier grows beyond 8× (to cut risk at deep grid levels).
- **Balanced exit:** if buy and sell counts are equal and the net position is profitable, closes everything immediately.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `PipValue` | 0.1 | Pip size for the symbol |
| `ReentryPips` | 87 | Pip distance before adding next martingale order |
| `ExitProfitPips` | 38 | Aggregate pip profit target to close all orders |
| `MagicNumber` | 12345 | EA identifier |
| `Slippage` | 3 | Max slippage in points |
| `MA_Period` | 6 | Period of the trigger SMA |

## Chart features

- **Progress bar** in chart comment showing how close the position is to the exit target.
- **Simulated level lines** (orange for sells, cyan for buys) showing where the next martingale entries would be placed and the projected equity at each level.
- **Blowout line** (red, thick): the price at which simulated equity would reach zero — a visual warning of account risk.
- **"Close All Trades and Reset" button** on the chart to manually flatten all positions.

## Risk warning

This EA uses martingale. Lot sizes double at every adverse step, which can grow exponentially. The blowout line on the chart indicates the price at which the account would be wiped.
