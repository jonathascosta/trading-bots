# CyclesTheoryMartingale

**Platform:** MetaTrader 4  
**Version:** 2.1  
**Last updated:** 2025-04-13

## What it does

The earliest working version of the Cycles Theory EA. It defines a weekly Opening Channel from the first 4 M15 candles after Monday 00:00, then trades breakouts of that channel in a cascaded 3-order setup with progressive stop-loss management and martingale on loss.

This is the predecessor to [Cycles.mq4](../Cycles/README.md) and [CyclesExpertAdvisor.mq4](../CyclesExpertAdvisor/README.md).

## Key differences from later versions

- Channel is built from **candle bodies** (open/close) instead of full wicks.
- No weekly profit tracking or weekly risk cap.
- No prop-firm mode or auto-lot calculation.
- Simpler state machine, easier to read.

## Strategy logic

### Phase 1 — Define the Opening Channel (CA)

On Monday, scans M15 bars from the week start. The first 4 bars found after Monday 00:00 determine:
- `CA_High` = max of all candle body highs
- `CA_Low` = min of all candle body lows
- `BaseDiff` = `CA_High − CA_Low`

### Phase 2 — Calculate C1/C2/C3 levels

Cycle levels are placed at multiples of `BaseDiff`:

```
C3_up  = C2_up  + 4 × BaseDiff     C3_down = C2_down − 4 × BaseDiff
C2_up  = C1_up  + 2 × BaseDiff     C2_down = C1_down − 2 × BaseDiff
C1_up  = CA_High + BaseDiff        C1_down = CA_Low  − BaseDiff
━━━━━━━━━━ CA_High ━━━━━━━━━━
━━━━━━━━━━ CA_Low  ━━━━━━━━━━
```

### Phase 3 — Wait for breakout and entry

When price breaks out of the CA (above `CA_High` or below `CA_Low`), the EA enters `ST_WAIT_C1`. It then waits for the previous M5 candle to close beyond C1:
- Close above `C1_up` → open 3 BUY orders
- Close below `C1_down` → open 3 SELL orders

Each set of 3 orders shares the same lot size and entry price. Their TPs differ:
- Order 0: TP at C2
- Order 1: TP at C3
- Order 2: no TP (managed by trailing stop)

SL for all 3: opposite CA edge ± `BaseDiff / 2`

### Phase 4 — Progressive SL management

| Price reaches | Action |
|---|---|
| C2 | Move SL of orders 1 and 2 to break-even (`openPrice + BaseDiff/2`) |
| C3 | Move SL of order 2 to C2; activate trailing stop (4 × BaseDiff) |

### Phase 5 — After all orders close

- **If loss:** multiply `CurrentLot` by `LotMultiplier` (martingale) and return to `ST_IDLE` immediately.
- **If profit:** reset lot to `BaseLot`, wait for M5 to close back inside CA (`ST_WAIT_BACK_IN`), then restart.

### Full state machine

```
┌─────────────────────────────────────────────────────┐
│                     ST_IDLE                         │
│  Wait for Monday, define CA and C1/C2/C3 levels    │
│  On price crossing CA boundary → ST_WAIT_C1         │
└───────────────────────┬─────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│                   ST_WAIT_C1                        │
│  Monitor for M5 candle close beyond C1_up/C1_down  │
│  On confirmation → open 3 orders → ST_OPENED        │
└───────────────────────┬─────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│                   ST_OPENED                         │
│  Manage progressive SLs and trailing stop          │
│  When all 3 orders close:                          │
│    Loss  → x2 lot → ST_IDLE                        │
│    Profit → reset lot → ST_WAIT_BACK_IN             │
└───────────────────────┬─────────────────────────────┘
                        │ (profit path)
                        ▼
┌─────────────────────────────────────────────────────┐
│               ST_WAIT_BACK_IN                       │
│  Wait for M5 candle to re-enter the CA range       │
│  On re-entry → ST_IDLE                              │
└─────────────────────────────────────────────────────┘
```

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `BaseLot` | 0.1 | Starting lot size |
| `LotMultiplier` | 2.0 | Martingale multiplier on loss |
| `MagicNumber` | 20250413 | EA identifier |
| `EnableAlerts` | true | Alert on trade open |
