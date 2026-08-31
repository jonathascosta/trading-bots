# AurumLegLimit — Changelog

## v1.00 — 2026-07-19
- Initial prototype, companion to AurumLeg (separate magic 20260719, runs in parallel).
- Signal: freshly confirmed pivot ending an impulse >= 3.0 x medLeg (threshold from swing research: retracements after such impulses land in the 30-80% band 60-65% of the time vs 40-45% mechanical baseline; below 3x the anomaly vanishes and the simulated variant loses).
- Entry: limit order at 55% retracement of the impulse, lifetime 36 bars (3h). SL beyond 100% retracement (0.25 x medLeg buffer), TP at the impulse extreme (beat TP=1.5xmedLeg in all 6 simulated grid cells).
- Same filters as AurumLeg: medLeg >= $8, blocked hours 0/13-16, max spread 35 pts, max 5 positions, risk sizing 1.5% (fallback fixed lot).
- Simulated (8 months M5): PF 1.2-1.3, ~0.8 trades/day, ~+16% on top of AurumLeg's stream. Small n (139-193) — validate in Strategy Tester, then forward.
