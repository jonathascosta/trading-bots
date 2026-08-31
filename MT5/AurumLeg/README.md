# AurumLeg

**Platform:** MetaTrader 5  
**Version:** 1.02  
**Last updated:** 2026-07-17  

## What it does

Swing-continuation EA for **XAUUSD M5**. Builds a zigzag from 3-bar swing points (strict min/max alternation) and fires a market entry whenever the latest confirmed pivot shows a 38–62% retracement of the previous leg — the "golden zone" — signalling trend continuation.

TP and SL are set symmetrically at `1.5 × medLeg`, where `medLeg` is the median size of the last 20 completed legs. Position sizing defaults to 1.5% of equity per trade based on the SL distance (falls back to fixed `InpLots` when `InpRiskPercent = 0`).

Backtest basis (8 months M5): PF 1.17–1.18, ~1 900 trades, 1/10 negative months.

## Filters

- `medLeg` must be ≥ $8 (ensures meaningful legs, not choppy noise)
- Blocked server hours: 0 (Sydney open spread spike), 13–16 (US news + NY open)
- Max spread: 35 points
- Max simultaneous positions: 5 (configurable)
- `InpOnePerPivot` (default `true`): skip re-signals when a pivot deepens but does not yet close a new leg — prevents multiple entries on the same swing

## Configuration

| Input | Default | Description |
|---|---|---|
| `InpLots` | 0.01 | Fixed lot (fallback when risk % = 0) |
| `InpRiskPercent` | 1.5 | Risk % of equity per trade; 0 = use InpLots |
| `InpRetrMin` | 38.0 | Min retracement % to signal |
| `InpRetrMax` | 62.0 | Max retracement % to signal |
| `InpTPMult` | 1.5 | TP as a multiple of medLeg |
| `InpSLMult` | 1.5 | SL as a multiple of medLeg |
| `InpLegsWindow` | 20 | Rolling window for the leg median |
| `InpMinMedLeg` | 8.0 | Min medLeg in $ to allow entries |
| `InpBlockedHours` | `"0,13,14,15,16"` | Comma-separated blocked server hours |
| `InpMaxSpreadPts` | 35 | Max spread in points to enter |
| `InpMaxPositions` | 5 | Max simultaneous positions (0 = unlimited) |
| `InpOnePerPivot` | true | Skip re-signals on deepening pivots |
| `InpWarmupBars` | 1000 | History bars to rebuild zigzag state on init |
| `InpMagic` | 20260717 | Magic number |

See [CHANGELOG.md](CHANGELOG.md) for version history.
