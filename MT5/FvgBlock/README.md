# FvgBlock

**Platform:** MetaTrader 5  
**Version:** 3.80  
**Last updated:** 2026-05-30

## What it does

Fair Value Gap + Order Block EA designed for **XAUUSD on M1**. It scans every completed bar for a 3-candle Fair Value Gap (FVG) pattern, identifies the most recent valid unfilled block, and enters both sides of the block zone simultaneously with limit orders. If price moves against either side, it scales in by doubling the lot at a configurable distance, updating the collective take-profit to the weighted break-even.

## Core concepts

**Fair Value Gap (FVG):** A gap between bar[0] low and bar[2] high (bullish) or bar[0] high and bar[2] low (bearish), where bar[1] is the imbalance candle.

**Order Block:** The full High–Low range of all bars since the FVG bar. This expands as new extremes are made. The block must be at least `InpBlkMinSize` pips wide to be tradeable.

**Zone structure:**

```
  ┌───────────────────────────────────────────┐  ← blockHigh
  │  TOP zone  (InpZonePercent of block size)  │  ← SELL entries here
  ├───────────────────────────────────────────┤  ← topBand
  │                                           │
  │         BODY  (mid ± ZonePercent)         │  ← TP target
  │                                           │
  ├───────────────────────────────────────────┤  ← botBand
  │  BOT zone  (InpZonePercent of block size)  │  ← BUY entries here
  └───────────────────────────────────────────┘  ← blockLow
```

## State machine

```
IDLE ──────────────────────────────────────────────────────────────────┐
  New block detected, trading window open, no news?                    │
  Place SELL LIMIT at topBand (or market if already inside zone)       │
  Place BUY  LIMIT at botBand (or market if already inside zone)       │
         │                                                             │
         ▼                                                             │
PENDING  (one or both limit orders waiting)                            │
  Update limit prices as block expands                                 │
  If zone is breached → swap limit for market order                    │
         │ order fills                                                  │
         ▼                                                             │
STATE_SELLS or STATE_BUYS (one side active)                           │
  Cancel the opposing side's pending order                             │
  TP logic:                                                            │
    If midTop/midBot is favourable vs first entry → freeze TP at BE   │
    Otherwise keep TP at midTop/midBot                                 │
  Scale-in (martingale):                                               │
    If last position is InpMinOrderDistance pips adverse →            │
    open new position with 2× previous lot, update all TPs to new BE  │
         │ all positions closed                                         │
         └──────────────────────────────────────────────────────────────┘
```

## Filters

**Time filter:** Trading is allowed between `InpTradeStartHour:InpTradeStartMinute` and `InpTradeStopHour:InpTradeStopMinute` (defaults: 01:15 – 19:45, local time).

**Force close:** At `InpForceCloseHour:InpForceCloseMinute` (default 20:45):
- If today is net profitable (realised + floating) → close all and stop.
- If today is net negative → block new cycles but allow existing scale-ins to recover.

**News filter:** Hardcoded calendar of high-impact USD events (NFP, CPI, PPI, FOMC, PCE, ISM) through June 2026. Blocks new orders and cancels pending ones within ±15 minutes of each event.

## Parameters

| Group | Parameter | Default | Description |
|---|---|---|---|
| FVG | `InpFvgMinSize` | 0.0 | Min FVG gap size in pips (0 = any) |
| Block | `InpBlkMinSize` | 39.0 | Min block height in pips to trade |
| Block | `InpZonePercent` | 5.0 | % of block used as entry/TP zone |
| Block | `InpPipValue` | 0.10 | Point value for pip conversion |
| Block | `InpBarsFuture` | 50 | How far to draw the block rectangle |
| Trading | `InpInitialLots` | 0.01 | Starting lot size |
| Trading | `InpMinOrderDistance` | 130.0 | Pips between scale-in levels |
| Trading | `InpCostPerLot` | 0.06 | Round-trip cost per 0.01 lot (commission + spread) |
| Trading | `InpMagicNumber` | 20250528 | EA identifier |
| Time | `InpTradeStartHour/Minute` | 1:15 | Trading window start |
| Time | `InpTradeStopHour/Minute` | 19:45 | Trading window end |
| Time | `InpForceCloseHour/Minute` | 20:45 | Force-close time |
| Time | `InpServerOffset` | 3 | Broker UTC offset |
| Time | `InpUtcOffset` | 1 | Local UTC offset |
| News | `InpEnableNewsFilter` | true | Block around USD news events |

## Lot sizing recommendation

The EA prints a warning and shows an on-chart label if `InpInitialLots` is below the recommended value, computed as:

```
Recommended = ROUND((Balance − 400) / 800, 0) / 100 + 0.01
```

## Risk warning

The scale-in doubles lot size on each adverse step. With `InpMaxOrders` not enforced at the code level (only `InpMinOrderDistance` limits frequency), deep grids are possible if price trends strongly against the open side.
