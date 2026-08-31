# AurumLeg — Changelog

## v1.02 — 2026-07-17
- Risk-based position sizing: `InpRiskPercent` (default 1.5% of equity per trade, computed from SL distance via tick size/value). Set 0 to fall back to fixed `InpLots`.
- Default 1.5% calibrated per user request for historical max DD up to ~50% (observed DD ~30 risk units x 1.5%); worst-case simultaneous exposure = 5 positions x 1.5% = 7.5%. For prop-firm limits use 0.15-0.25%.
- If the risk budget is below the symbol's minimum volume the trade is skipped (never oversized).

## v1.01 — 2026-07-17
- `InpOnePerPivot` (default true): skip re-signals when a pivot deepens into a more extreme value (leg history still updated). Simulated: PF 1.17 -> 1.18, max concurrent positions 11 -> 9.
- `InpMaxPositions` default changed 0 -> 5. Combined with one-per-pivot: n=1788, PF 1.18, total -4% vs v1.00, max concurrent 5.
- Tested and rejected: minimum price distance between same-direction entries (0.75 x medLeg) — cuts profit ~50% without improving PF; nearby signals from distinct pivots are good trades.

## v1.00 — 2026-07-17
- Initial prototype. Golden-zone swing continuation on M5 XAUUSD, derived from SwingRangePct swing research (8 months M5 backtest: PF 1.17, 1909 trades, 1/10 negative months).
- Zigzag from 3-bar swing points, strict min/max alternation, same-bar min+max supported (same algorithm as SwingRangePct indicator).
- Signal: confirmed pivot (1-bar lag) with retracement 38-62% of previous leg -> market entry at next bar open in continuation direction.
- TP/SL = 1.5 x medLeg (median of last 20 legs), symmetric.
- Filters: medLeg >= $8, blocked server hours 0 (Sydney open spread spike) and 13-16 (US news window + NY open), max spread 35 pts, optional max positions cap.
- Warmup rebuilds zigzag state from 1000 history bars on init.
