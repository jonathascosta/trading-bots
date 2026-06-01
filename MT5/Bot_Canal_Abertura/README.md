# Bot Canal Abertura v2

**Platform:** MetaTrader 5  
**Version:** 5.00  
**Last updated:** 2026-01-23

## What it does

Intraday Opening Channel breakout EA for MT5. Every trading day it reads the first 4 completed candles to define the day's "Opening Channel" (CA), then enters a pending order on a breakout. If the trade closes at a loss, it reverses direction and doubles the lot (up to a configurable maximum of "Viradas").

## State machine

```
┌──────────────────────────────────────────────────────┐
│             AGUARDANDO_VELAS                         │
│  Wait for 4 completed candles to form the CA        │
│  (resets every new day)                             │
└───────────────────────┬──────────────────────────────┘
                        │ 4 candles formed
                        ▼
┌──────────────────────────────────────────────────────┐
│           MONITORANDO_ROMPIMENTO                     │
│  Watch for previous candle close beyond CA top/bot  │
│  Place BUY STOP or SELL STOP                        │
└───────────────────────┬──────────────────────────────┘
                        │ order fills
                        ▼
┌──────────────────────────────────────────────────────┐
│              POSICAO_ABERTA                          │
│  A) Break-even: move SL to open when 50% of C2      │
│     distance is reached                             │
│  B) On close:                                       │
│     Profit → FINALIZADO_DIA                         │
│     Loss & viradas < max → double lot + reverse     │
│     Loss & viradas exhausted → FINALIZADO_DIA       │
└──────────────────────────────────────────────────────┘
```

## Opening Channel logic

1. Reads the first 4 candles of the current day on the chart's timeframe.
2. `CA_High` = highest high, `CA_Low` = lowest low across those 4 candles.
3. `Range` = `CA_High − CA_Low`.

**If range ≤ timeframe limit** (M1: 500 pts, M5: 1000 pts, M15: 2000 pts):  
Normal mode — wait for breakout, then place entry at `CA_High + Range` (BUY STOP) or `CA_Low − Range` (SELL STOP). TP = entry ± `2 × Range`; SL = opposite CA edge.

**If range > limit** (channel too large):  
Sliced mode — split at midpoint. Uses the 4th candle's close to decide bias, then places a market entry immediately at the original extreme with TP = entry ± `2 × half-range`.

## Virada (reversal/martingale)

On a loss, the EA looks at the current price relative to `CA_Top` and `CA_Bottom` to decide reversal direction (trades toward the nearer wall), and the lot is `BaseLot × 2^viradaCount`. Capped at `InpMaxLote`.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `InpModoVolume` | PERCENTUAL | Fixed lot or % of equity |
| `InpLotesFixos` | 0.01 | Lot when using fixed mode |
| `InpRiscoPerc` | 1.0 | Risk % of equity for first order |
| `InpMaxLote` | 50.0 | Maximum lot cap |
| `InpMaxViradas` | 3 | Max loss reversals per day |
| `InpMargemTP_Perc` | 10.0 | TP reduction margin (%) |
| `InpUsarBreakEven` | true | Enable break-even move |
| `InpLimite_M1/M5/M15` | 500/1000/2000 | Range limit per timeframe (points) |
| `InpSlippage` | 10 | Max slippage |
