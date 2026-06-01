# XAUUSD Exhaustion Grid

**Platform:** MetaTrader 5  
**Version:** 1.70  
**Last updated:** 2026-03-15

## What it does

Grid EA designed for **XAUUSD**. It monitors for price exhaustion moves beyond a configurable offset (`X`) and builds a recovery grid, adding new positions every `Z` pips. Each position targets `Y` pips of profit. Volume can optionally double every N orders.

## Entry logic

The EA opens one trade per bar (limited to one per candle to avoid flooding). An entry is triggered when price moves beyond an extreme threshold defined by `InpXOffset`. Both buys and sells can be active simultaneously on opposite sides.

## Grid management

```
First entry opens at current price
  │
  ├─ Price moves Z pips further against position?
  │     → Open next grid order (same direction)
  │     → Optionally double the lot every InpVolumeDoubleStep orders
  │
  └─ Price reaches TP (Y pips from each entry)?
        → Individual position closes at profit
```

Each position has its own independent TP (`Y` pips from its own entry). There is no shared break-even or collective close mechanism — positions close individually as price retraces to each TP level.

## Filters

**Time filter:** Configurable trading window (default 01:00–23:00 server time). Supports windows that wrap across midnight (e.g. 22:00–05:00).

**News filter (Economic Calendar):** Uses the MQL5 built-in `CalendarValueHistory()` API — no hardcoded dates. When `InpUseNewsFilter = true`, the EA pauses for `InpNewsBeforeMin` minutes before and `InpNewsAfterMin` minutes after any calendar event with impact level ≥ `InpNewsImpact` (default: High Impact only). This is dynamic and auto-updates as the broker's calendar is updated.

## Parameters

| Group | Parameter | Default | Description |
|---|---|---|---|
| Triggers | `InpXOffset` | 0.1 | Extreme offset to trigger initial entry |
| Time | `InpUseTimeFilter` | true | Enable trading hours filter |
| Time | `InpStartTime` | 01:00 | Trading start (HH:MM, server time) |
| Time | `InpEndTime` | 23:00 | Trading end (HH:MM, server time) |
| News | `InpUseNewsFilter` | false | Enable MQL5 calendar news filter |
| News | `InpNewsBeforeMin` | 60 | Pause X minutes before news |
| News | `InpNewsAfterMin` | 30 | Pause X minutes after news |
| News | `InpNewsImpact` | 3 | Min impact level (3 = High) |
| TP | `InpYTP` | 1.0 | Profit target per position (price units) |
| Grid | `InpZStep` | 6.8 | Grid step (price units) |
| Grid | `InpMaxOrders` | 100 | Maximum open positions cap |
| MT5 | `InpLotSize` | 0.01 | Initial lot size |
| MT5 | `InpVolumeDoubleStep` | 25 | Double lot every N orders (0 = off) |
| MT5 | `InpMagic` | 20260306 | EA identifier |

## Risk warning

This is an unbounded grid with no stop-loss and optional lot doubling. In a sustained trend, the number of open positions and total drawdown grow rapidly. The `InpMaxOrders` cap is the only hard safety limit.
