# Cycles

**Platform:** MetaTrader 4  
**Version:** 3.0  
**Last updated:** 2025-05-04

## What it does

Second-generation Cycles Theory EA. Adds weekly risk tracking, prop-firm mode, auto-lot sizing, and improved channel definition (using full wicks) compared to [CyclesTheoryMartingale.mq4](../CyclesTheoryMartingale/README.md).

The strategy waits for Monday, locks in the weekly "Opening Channel" from the first 4 M15 bars, then trades breakouts at C1 with a 3-order cascade and progressive stop-loss management.

## How it differs from CyclesTheoryMartingale

| Feature | CyclesTheoryMartingale | Cycles |
|---|---|---|
| Channel definition | Candle bodies | Full wicks (High/Low) |
| Weekly risk cap | No | Yes |
| Prop firm mode | No | Yes |
| Auto lot calculation | No | Yes (`AutoCalculateLot`) |
| Version | 2.1 | 3.0 |

## Strategy logic

### Channel definition

The Opening Channel (CA) is formed from the first 4 M15 candles after Monday 00:00 (server time). Uses `iHigh`/`iLow` — full wicks — so the channel is slightly wider than in v2.1.

C1, C2, C3 are placed at the same multiples of `BaseDiff`:

```
C3_up  = C2_up  + 4 × BaseDiff
C2_up  = C1_up  + 2 × BaseDiff
C1_up  = CA_High + BaseDiff
━━━━━━━━━━━ CA_High ━━━━━━━━━━━
━━━━━━━━━━━ CA_Low  ━━━━━━━━━━━
C1_down = CA_Low  − BaseDiff
C2_down = C1_down − 2 × BaseDiff
C3_down = C2_down − 4 × BaseDiff
```

### Entry, SL management, and trailing stop

Identical to [CyclesTheoryMartingale](../CyclesTheoryMartingale/README.md) — see its state machine diagram.

### Risk management additions

- **`AutoCalculateLot`:** lot is sized so that losing the SL distance costs `RiskPercent / 3` of effective balance (3 orders share the risk).
- **`IsPropFirm`:** effective balance = `AccountBalance × PropFirmMaxLossPercentage / 100`.
- **Weekly target:** once `weeklyPnl ≥ totalRiskMoney` the EA stops trading and shows "Weekly target reached" until Monday.
- **Martingale on loss:** lot doubles (up to `LotMultiplier`) after a losing cycle; resets on profit.
- **Weekly reset:** every Monday, all state is cleared and the channel is redefined.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `BaseLot` | 0.1 | Starting lot (ignored if `AutoCalculateLot = true`) |
| `LotMultiplier` | 2.0 | Martingale multiplier on loss |
| `AutoCalculateLot` | false | Size lot by risk percentage |
| `RiskPercent` | 1.0 | % of balance risked per 3-order cycle |
| `IsPropFirm` | false | Cap effective balance by max drawdown % |
| `PropFirmMaxLossPercentage` | 6.0 | Max drawdown % for prop firm accounts |
| `MagicNumber` | 20250426 | EA identifier |
| `EnableAlerts` | true | Alert on trade open |
| `QualityFalseBreakThreshold` | 2 | (reserved for future use) |
| `QualityExtendedBarsCount` | 4 | Number of opening candles to analyse |
