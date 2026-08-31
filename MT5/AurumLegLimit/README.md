# AurumLegLimit

**Platform:** MetaTrader 5  
**Version:** 1.00  
**Last updated:** 2026-07-23  
**Companion to:** [AurumLeg](../AurumLeg/)

## What it does

Companion EA to AurumLeg that captures deep retracements after strong impulses on **XAUUSD M5**. When a freshly confirmed pivot ends an impulse leg ≥ 3× the rolling leg median, a limit order is placed at 55% retracement of that impulse, with SL just beyond the 100% retracement level and TP at the impulse extreme.

Research basis: after impulses ≥ ~3× medLeg, the next retracement lands in the 30–80% band 60–65% of the time (vs ~13% mechanical baseline for the largest legs). Below 3× the anomaly vanishes and the simulated strategy loses.

Simulated (8 months M5): PF 1.2–1.3, ~0.8 trades/day, adds ~+16% on top of AurumLeg's stream.

## Usage

Designed to run in **parallel with AurumLeg** on the same chart — different magic number (20260719) so positions are tracked independently.

## Configuration

| Input | Default | Description |
|---|---|---|
| `InpLots` | 0.01 | Fixed lot (fallback when risk % = 0) |
| `InpRiskPercent` | 1.5 | Risk % of equity per trade |
| `InpImpulseMult` | 3.0 | Min impulse size relative to medLeg |
| `InpRetrFrac` | 0.55 | Limit placement as a fraction of the impulse |
| `InpSLBufMult` | 0.25 | SL buffer beyond 100% retracement (× medLeg) |
| `InpExpiryBars` | 36 | Pending order lifetime in bars (36 = 3 h on M5) |
| `InpLegsWindow` | 20 | Rolling window for the leg median |
| `InpMinMedLeg` | 8.0 | Min medLeg in $ to allow entries |
| `InpBlockedHours` | `"0,13,14,15,16"` | Blocked server hours |
| `InpMaxSpreadPts` | 35 | Max spread in points |
| `InpMaxPositions` | 5 | Max simultaneous positions |
| `InpWarmupBars` | 1000 | History bars to rebuild zigzag state |
| `InpMagic` | 20260719 | Magic number |

See [CHANGELOG.md](CHANGELOG.md) for version history.
