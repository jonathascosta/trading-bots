# PainelGridCompraVenda

**Platform:** MetaTrader 5  
**Version:** 2.00  
**Last updated:** 2025-12-24

## What it does

A **manual grid trading panel** — it does not auto-trade. It adds two clickable buttons to the chart ("COMPRAR" and "VENDER") and handles the grid distance validation and collective take-profit management automatically.

## How it works

### Buttons

| Button | Colour | Action |
|---|---|---|
| COMPRAR | Green | Opens a BUY at market |
| VENDER | Red | Opens a SELL at market |

### Entry validation (distance guard)

Before sending an order, the EA checks:
- **BUY:** current Ask must be at least `InpGridDist` **below** the lowest open buy position's entry price.
- **SELL:** current Bid must be at least `InpGridDist` **above** the highest open sell position's entry price.

This prevents adding a new order too close to an existing one, maintaining the grid spacing.

### Automatic TP update

After every trade, `AtualizarTPs()` recalculates and applies a new take-profit to **all open positions of the same type**:

```
WeightedAvgPrice = Σ(price × volume) / Σ(volume)

TP for BUYs  = WeightedAvgPrice + InpTPValue
TP for SELLs = WeightedAvgPrice − InpTPValue
```

All positions of that type are modified to the new TP simultaneously. As more positions are added at worse prices, the TP moves to a distance above/below the new average, so the entire grid closes together when price recovers.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `InpLots` | 0.04 | Lot size per click |
| `InpTPValue` | 0.30 | Fixed distance above/below avg price for TP |
| `InpGridDist` | 1.00 | Minimum price distance between grid entries |
| `InpMagic` | 123456 | EA identifier |

## Notes

- No stop-loss is set. Grid positions can accumulate significant drawdown.
- The panel is designed for instruments quoted in price units (e.g. XAUUSD), so `InpTPValue` and `InpGridDist` are in price terms, not pips.
- Debug logging is verbose — the EA prints every button click event and validation step to the Experts log.
