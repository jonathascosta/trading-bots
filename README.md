# Trading Experts

MetaTrader Expert Advisors organized by platform. Source files only — compiled binaries are excluded.

```
trading/
├── MT4/
│   ├── Anti6MA/
│   ├── Cycles/
│   ├── CyclesExpertAdvisor/
│   └── CyclesTheoryMartingale/
└── MT5/
    ├── AurumBlock/
    ├── Bot_Canal_Abertura/
    ├── EveryCandle/
    ├── FvgBlock/
    ├── PainelGridCompraVenda/
    ├── RangeBreaker/
    └── XAUUSD_Exhaustion_Grid/
```

---

## MT4

### [Anti6MA](MT4/Anti6MA/)
Counter-trend martingale. Sells when a 6-period MA is rising, buys when it's falling. Doubles lot every `ReentryPips` adverse move. Closes the grid when aggregate pip profit crosses the target. Draws blowout levels and a progress bar on the chart.

### [CyclesTheoryMartingale](MT4/CyclesTheoryMartingale/)
First version of the Cycles Theory system (v2.1). Defines a weekly Opening Channel from the body of the first 4 M15 candles of Monday, then opens 3 simultaneous orders on a C1 breakout. Progressive SL management (break-even at C2, trailing after C3). Doubles lot after a losing cycle.

### [Cycles](MT4/Cycles/)
Second-generation Cycles Theory EA (v3.0). Same logic as CyclesTheoryMartingale but uses full wicks for the channel, adds weekly profit tracking, prop-firm mode, and optional auto-lot sizing based on a risk percentage.

### [CyclesExpertAdvisor](MT4/CyclesExpertAdvisor/)
OOP refactor of Cycles (v4.0). Same strategy, restructured into classes with swappable `IRiskManager` and `IChannelDefiner` interfaces. Requires companion `.mqh` include files in the MQL4 data directory.

---

## MT5

### [AurumBlock](MT5/AurumBlock/)
Production-hardened evolution of FvgBlock, built for XAUUSD M1. Adds session pause windows (±15 min around Tokyo, London, NY, NYSE opens), an asymmetric news filter (135 min before / 15 min after) driven by an external CSV calendar synced from the MT5 native calendar, a bottom-left statistics dashboard, and auto lot sizing. All settings are compile-time `#define` constants — no accidental parameter changes at runtime.

### [Bot_Canal_Abertura](MT5/Bot_Canal_Abertura/)
Intraday Opening Channel EA. Reads the first 4 candles of each day to define a range, then places pending orders at ±1× range. Moves to break-even at 50% of the target distance. On a losing trade, reverses direction and doubles the lot up to a configurable number of times ("Viradas").

### [EveryCandle](MT5/EveryCandle/)
Trades the direction of the previous candle at the open of every new candle. Closes the position when the originating timeframe's candle closes in profit. No take-profit — exit is purely event-driven. Can run on multiple timeframes simultaneously with independent lifecycles.

### [FvgBlock](MT5/FvgBlock/)
Fair Value Gap + Order Block EA for XAUUSD M1. Identifies the most recent unfilled FVG, enters both sides of the block zone with limit orders, and scales in by doubling the lot on adverse moves. Has a time window filter, a news filter (hardcoded USD events through mid-2026), and a daily force-close at 20:45.

### [PainelGridCompraVenda](MT5/PainelGridCompraVenda/)
Manual grid panel. Adds BUY and SELL buttons to the chart. Each click validates grid distance before entering, then recalculates and updates the take-profit of all open positions of that type to a fixed distance above/below the new weighted-average entry price. Does not auto-trade.

### [RangeBreaker](MT5/RangeBreaker/)
Session range breakout EA supporting up to 5 configurable sessions (default: Sydney, Tokyo, London, New York, NYSE). Measures the H/L of the first N candles of each session, places BUY STOP and SELL STOP at ±1× range, cancels the opposing order when one fills. Includes a live on-chart dashboard with per-session trade statistics. Contains two files: `RangeBreaker.mq5` (v1.33, current) and `SessionHighLowEA.mq5` (v1.0, earlier build kept for reference).

### [XAUUSD_Exhaustion_Grid](MT5/XAUUSD_Exhaustion_Grid/)
Exhaustion grid for XAUUSD. Opens initial entries on extreme moves and adds new positions every Z pips, with each position targeting Y pips of profit independently. Optional lot doubling every N orders. Uses the MQL5 Economic Calendar API for a dynamic news filter — no hardcoded dates.
