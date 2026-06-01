# CyclesExpertAdvisor

**Platform:** MetaTrader 4  
**Version:** 4.0  
**Last updated:** 2025-05-18

## What it does

The fully refactored, object-oriented version of the Cycles Theory EA. The trading logic is identical to [Cycles.mq4](../Cycles/README.md) but the code is restructured into classes with interfaces, making it easier to swap risk models and channel-definition methods without touching the core strategy.

## Architecture

```
OnInit()
  ├── Creates IRiskManager*
  │     ├── AccountRiskManager   (standard % of balance)
  │     └── PropFirmRiskManager  (% of max-drawdown limit)
  ├── Creates IChannelDefiner*
  │     ├── BodyChannelDefiner   (uses candle open/close bodies)
  │     └── WickChannelDefiner   (uses full High/Low wicks) ← default
  └── Creates CyclesExpertAdvisor(riskManager, channelDefiner, ...)
        └── OnTick() routes to processIdle / processWaitingToBreak /
                              processOpenTrades / processWaitingToRestart
```

## Behaviour

Functionally equivalent to Cycles.mq4 v3.0:

1. **Idle** — call `channelDefiner.Define(weekStart)` each tick until the channel is established.
2. **WaitingToBreak** — monitor for M5 candle close past C1 (high or low), then open `ordersQuantity` trades (default 3).
3. **Opened** — manage progressive SLs (break-even at C2, lock-in at C3, trailing 4×BaseDiff after C3).
4. **WaitingToRestart** — after a profitable cycle, wait for price to re-enter the channel, then reset.

Martingale and weekly risk cap behave exactly as in [Cycles.mq4](../Cycles/README.md).

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `AutoCalculateLot` | false | Use risk-based lot sizing |
| `RiskPercent` | 1.0 | % of balance risked per cycle |
| `IsPropFirm` | false | Enable prop firm balance cap |
| `PropFirmMaxLossPercentage` | 6.0 | Max drawdown % for prop firm |
| `BaseLot` | 0.1 | Fixed lot (when auto-calc is off) |
| `EnableAlerts` | true | Alert on trade open |
| `EnableMartingale` | true | Double lot after a loss |
| `LotMultiplier` | 2.0 | Martingale multiplier |
| `MagicNumber` | 20250426 | EA identifier |
| `QualityFalseBreakThreshold` | 2 | (reserved) |
| `QualityExtendedBarsCount` | 4 | Candles used for channel |

## Dependencies

Requires these include files to compile (must be in the `Experts/RiskManagers/` and `Experts/ChannelDefiners/` folders inside the MQL4 data directory):

```
RiskManagers/IRiskManager.mqh
RiskManagers/PropFirmRiskManager.mqh
RiskManagers/AccountRiskManager.mqh
ChannelDefiners/ChannelData.mqh
ChannelDefiners/IChannelDefiner.mqh
ChannelDefiners/BodyChannelDefiner.mqh
ChannelDefiners/WickChannelDefiner.mqh
```
