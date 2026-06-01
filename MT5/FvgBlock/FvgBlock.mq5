//+------------------------------------------------------------------+
//|                   FVG Block EA – XAUUSD M1  v3.80                |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "3.80"
#include <Trade\Trade.mqh>
//=== Inputs =========================================================
input group  "=== FVG Settings ==="
input double InpFvgMinSize       = 0.0;
input group  "=== Block Settings ==="
input double InpBlkMinSize       = 39.0;
input double InpZonePercent      = 5.0;
input double InpPipValue         = 0.10;
input int    InpBarsFuture       = 50;
input group  "=== Trading ==="
input double InpInitialLots      = 0.01;
input double InpMinOrderDistance = 130.0;
input double InpCostPerLot       = 0.06;   // Round-trip cost (commission+spread) per 0.01 lot
input int    InpMagicNumber      = 20250528;
input group  "=== Time Filter ==="
input int    InpTradeStartHour   = 1;
input int    InpTradeStartMinute = 15;
input int    InpTradeStopHour    = 19;
input int    InpTradeStopMinute  = 45;
input int    InpForceCloseHour   = 20;   // Force-close all positions at this hour (UTC+offset)
input int    InpForceCloseMinute = 45;   // Force-close all positions at this minute
input int    InpServerOffset     = 3;   // Broker server UTC offset (e.g. 3 for UTC+3)
input int    InpUtcOffset        = 1;   // Your local UTC offset (e.g. 1 for UTC+1)
input group  "=== News Filter ==="
input bool   InpEnableNewsFilter = true;   // Block ±15 min around high-impact USD events
input group  "=== Style ==="
input color  InpCMidBody         = C'255,152,0';
input color  InpCExtreme         = C'255,80,0';
input color  InpCUnstable        = clrYellow;
input color  InpCBelowMin        = clrSilver;
input color  InpCBorder          = C'255,152,0';
input int    InpBorderWidth      = 1;
//=== Structures =====================================================
struct FvgBlock {
    datetime startTime;
    double   gapTop, gapBottom, blockHigh, blockLow;
    bool     isBull, isFilled;
};
enum EState { STATE_IDLE, STATE_PENDING, STATE_SELLS, STATE_BUYS };
//=== Globals ========================================================
FvgBlock g_blocks[];
int      g_activeIdx     = -1;
datetime g_lastBarTime   = 0;
bool     g_initialized   = false;
bool     g_newFvgThisBar = false;
datetime g_activeSince   = 0;
double   g_botRefLow = 0, g_botRefHigh = 0, g_botExtLow = 0;
datetime g_botCreateTime = 0;
bool     g_botUnstable   = false;
double   g_topRefLow = 0, g_topRefHigh = 0, g_topExtHigh = 0;
datetime g_topCreateTime = 0;
bool     g_topUnstable   = false;
CTrade   g_trade;
EState   g_state         = STATE_IDLE;
bool     g_tpFrozen      = false;
bool     g_noNewCycles   = false;  // Set true after force-close when day is net negative
datetime g_prevBlockTime = 0;
#define N_MID   "FVG_MID"
#define N_MID_B "FVG_MID_BORD"
#define N_TOP   "FVG_TOP"
#define N_BOT   "FVG_BOT"
#define N_MBAND "FVG_MBAND"
#define N_INFO  "FVG_INFO"
#define N_LOTW  "FVG_LOTW"
#define N_SIZE  "FVG_SIZE"
#define N_PFX   "FVG_"
// ±15 min block window around each high-impact USD event (stored in UTC)
#define NEWS_WINDOW 900   // 15 * 60 seconds

// All times in UTC.
// Jan–Mar: EST (UTC-5) → 8:30 ET = 13:30 UTC, 10:00 ET = 15:00 UTC, 14:00 ET = 19:00 UTC
// Mar 8 onwards: EDT (UTC-4) → 8:30 ET = 12:30 UTC, 10:00 ET = 14:00 UTC, 14:00 ET = 18:00 UTC
const datetime NEWS_EVENTS[] =
{
    // ── January 2026 (EST = UTC-5) ────────────────────────────────
    D'2026.01.05 15:00',  // ISM Manufacturing PMI
    D'2026.01.09 13:30',  // NFP – Employment Report
    D'2026.01.13 13:30',  // CPI
    D'2026.01.14 13:30',  // PPI
    D'2026.01.28 19:00',  // FOMC Rate Decision
    D'2026.01.29 13:30',  // PCE
    // ── February 2026 (EST = UTC-5) ──────────────────────────────
    D'2026.02.02 15:00',  // ISM Manufacturing PMI
    D'2026.02.06 13:30',  // NFP
    D'2026.02.11 13:30',  // CPI
    D'2026.02.12 13:30',  // PPI
    D'2026.02.26 13:30',  // PCE
    // ── March 2026 (EST until Mar 7 → EDT from Mar 8) ────────────
    D'2026.03.02 15:00',  // ISM Manufacturing PMI (EST)
    D'2026.03.06 13:30',  // NFP (EST)
    D'2026.03.11 12:30',  // CPI (EDT)
    D'2026.03.12 12:30',  // PPI (EDT)
    D'2026.03.18 18:00',  // FOMC Rate Decision (EDT)
    D'2026.03.27 12:30',  // PCE (EDT)
    // ── April 2026 (EDT = UTC-4) ──────────────────────────────────
    D'2026.04.01 14:00',  // ISM Manufacturing PMI
    D'2026.04.03 12:30',  // NFP
    D'2026.04.10 12:30',  // CPI
    D'2026.04.14 12:30',  // PPI
    D'2026.04.29 18:00',  // FOMC Rate Decision
    D'2026.04.30 12:30',  // PCE
    // ── May 2026 (EDT = UTC-4) ────────────────────────────────────
    D'2026.05.01 14:00',  // ISM Manufacturing PMI
    D'2026.05.08 12:30',  // NFP
    D'2026.05.12 12:30',  // CPI
    D'2026.05.13 12:30',  // PPI
    D'2026.05.28 12:30',  // PCE
    // ── June 2026 (EDT = UTC-4) ───────────────────────────────────
    D'2026.06.01 14:00',  // ISM Manufacturing PMI
    D'2026.06.05 12:30',  // NFP
    D'2026.06.10 12:30',  // CPI
    D'2026.06.11 12:30',  // PPI
    D'2026.06.17 18:00',  // FOMC Rate Decision
    D'2026.06.25 12:30',  // PCE
};

//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
    MqlDateTime dt;
    // Use TimeCurrent() (broker server time) adjusted to local time.
    // Avoids relying on TimeGMT() which depends on the broker correctly
    // reporting TimeGMTOffset() — not always reliable.
    TimeToStruct(TimeCurrent() + (datetime)((InpUtcOffset - InpServerOffset) * 3600), dt);
    int current = dt.hour * 60 + dt.min;
    int start   = InpTradeStartHour * 60 + InpTradeStartMinute;
    int stop    = InpTradeStopHour  * 60 + InpTradeStopMinute;
    if(start == stop) return true;
    if(start < stop)
        return (current >= start && current < stop);
    // Overnight window: e.g. 23:15 → 21:30, inactive only 21:30 – 23:15
    return (current >= start || current < stop);
}
bool IsNewsTime()
{
    if(!InpEnableNewsFilter) return false;
    // NEWS_EVENTS are stored in UTC → convert server time to UTC
    datetime now = TimeCurrent() - (datetime)(InpServerOffset * 3600);
    int n = ArraySize(NEWS_EVENTS);
    for(int i = 0; i < n; i++)
    {
        long diff = MathAbs((long)now - (long)NEWS_EVENTS[i]);
        if(diff <= NEWS_WINDOW) return true;
    }
    return false;
}
// True from InpForceCloseHour:InpForceCloseMinute until trading restarts (InpTradeStartHour:InpTradeStartMinute).
// Covers the window 20:45 – 23:15 where all open positions must be closed.
bool IsForceCloseTime()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent() + (datetime)((InpUtcOffset - InpServerOffset) * 3600), dt);
    int current = dt.hour * 60 + dt.min;
    int force   = InpForceCloseHour   * 60 + InpForceCloseMinute;   // 20:45 = 1245
    int start   = InpTradeStartHour   * 60 + InpTradeStartMinute;   // 01:15 = 75
    if(force == start) return false;
    if(force < start)
        // Simple window (no midnight wrap): e.g. 02:00 → 08:00
        return (current >= force && current < start);
    // Overnight window (wraps midnight): e.g. 20:45 → 01:15
    // Active when: current >= 20:45 OR current < 01:15
    return (current >= force || current < start);
}
void CloseAllPositions()
{
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL)  != Symbol())       continue;
        if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
        g_trade.PositionClose(t);
    }
}
// Returns the recommended initial lot based on current balance:
//   ROUND((Balance - 400) / 800, 0) / 100 + 0.01
double RecommendedLots()
{
    double bal = AccountInfoDouble(ACCOUNT_BALANCE);
    double rec = MathRound((bal - 400.0) / 800.0) / 100.0 + 0.01;
    return NormalizeDouble(MathMax(rec, 0.01), 2);
}
//+------------------------------------------------------------------+
void BoxSet(const string name, datetime t1, double p1, datetime t2, double p2,
            color clr, bool fill, int bw = 0)
{
    if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
    ObjectSetInteger(0, name, OBJPROP_TIME,       0, t1);
    ObjectSetDouble( 0, name, OBJPROP_PRICE,      0, p1);
    ObjectSetInteger(0, name, OBJPROP_TIME,       1, t2);
    ObjectSetDouble( 0, name, OBJPROP_PRICE,      1, p2);
    ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
    ObjectSetInteger(0, name, OBJPROP_FILL,       fill);
    ObjectSetInteger(0, name, OBJPROP_WIDTH,      bw);
    ObjectSetInteger(0, name, OBJPROP_BACK,       true);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}
void BoxDel(const string n) { if(ObjectFind(0,n)>=0) ObjectDelete(0,n); }
void DeleteAllBoxes()
{
    BoxDel(N_MID); BoxDel(N_MID_B); BoxDel(N_TOP);
    BoxDel(N_BOT); BoxDel(N_MBAND); BoxDel(N_INFO); BoxDel(N_LOTW); BoxDel(N_SIZE);
}
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
{
    int c = 0;
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL)   != Symbol())           continue;
        if(PositionGetInteger(POSITION_MAGIC)   != InpMagicNumber)     continue;
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==type) c++;
    }
    return c;
}
int CountPending(ENUM_ORDER_TYPE type)
{
    int c = 0;
    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        ulong t = OrderGetTicket(i);
        if(!OrderSelect(t)) continue;
        if(OrderGetString(ORDER_SYMBOL)  != Symbol())       continue;
        if(OrderGetInteger(ORDER_MAGIC)  != InpMagicNumber) continue;
        if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)==type) c++;
    }
    return c;
}
ulong GetPendingTicket(ENUM_ORDER_TYPE type)
{
    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        ulong t = OrderGetTicket(i);
        if(!OrderSelect(t)) continue;
        if(OrderGetString(ORDER_SYMBOL)  != Symbol())       continue;
        if(OrderGetInteger(ORDER_MAGIC)  != InpMagicNumber) continue;
        if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)==type) return t;
    }
    return 0;
}
void DeleteAllPending(ENUM_ORDER_TYPE type)
{
    ulong t = GetPendingTicket(type);
    while(t != 0) { g_trade.OrderDelete(t); t = GetPendingTicket(type); }
}
bool GetLastPosition(ENUM_POSITION_TYPE type, double &price, double &lots, datetime &openTime)
{
    price = 0; lots = 0; openTime = 0;
    bool found = false;
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL)  != Symbol())       continue;
        if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type) continue;
        datetime pt = (datetime)PositionGetInteger(POSITION_TIME);
        if(pt >= openTime)
        {
            openTime = pt; price = PositionGetDouble(POSITION_PRICE_OPEN);
            lots = PositionGetDouble(POSITION_VOLUME); found = true;
        }
    }
    return found;
}
double GetFirstPositionEntry(ENUM_POSITION_TYPE type)
{
    double   entry    = 0;
    datetime earliest = 0;
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL)  != Symbol())       continue;
        if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type) continue;
        datetime pt = (datetime)PositionGetInteger(POSITION_TIME);
        if(earliest == 0 || pt < earliest) { earliest = pt; entry = PositionGetDouble(POSITION_PRICE_OPEN); }
    }
    return entry;
}
double GetTotalVolume(ENUM_POSITION_TYPE type)
{
    double v = 0;
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL)  != Symbol())       continue;
        if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==type) v += PositionGetDouble(POSITION_VOLUME);
    }
    return v;
}
double GetWeightedBreakEven(ENUM_POSITION_TYPE type)
{
    double tv = 0, ws = 0;
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL)  != Symbol())       continue;
        if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type) continue;
        double v = PositionGetDouble(POSITION_VOLUME);
        ws += v * PositionGetDouble(POSITION_PRICE_OPEN);
        tv += v;
    }
    return tv > 0 ? ws / tv : 0;
}
void UpdateAllTPs(ENUM_POSITION_TYPE type, double newTP)
{
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL)  != Symbol())       continue;
        if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type) continue;
        if(MathAbs(PositionGetDouble(POSITION_TP) - newTP) > 0.00001)
            g_trade.PositionModify(t, 0, newTP);
    }
}
void UpdatePendingOrder(ENUM_ORDER_TYPE type, double newPrice, double newTP)
{
    ulong t = GetPendingTicket(type);
    if(t == 0) return;
    if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - newPrice) > 0.00001 ||
       MathAbs(OrderGetDouble(ORDER_TP)          - newTP)   > 0.00001)
        g_trade.OrderModify(t, newPrice, 0, newTP, ORDER_TIME_GTC, 0);
}
//+------------------------------------------------------------------+
void BlockAdd(datetime st, double gt, double gb, double bh, double bl, bool bull)
{
    int n = ArraySize(g_blocks);
    ArrayResize(g_blocks, n+1);
    g_blocks[n].startTime = st; g_blocks[n].gapTop    = gt;
    g_blocks[n].gapBottom = gb; g_blocks[n].blockHigh = bh;
    g_blocks[n].blockLow  = bl; g_blocks[n].isBull    = bull;
    g_blocks[n].isFilled  = false;
}
//+------------------------------------------------------------------+
void ProcessBar(int shift)
{
    const string sym = Symbol();
    const ENUM_TIMEFRAMES per = Period();
    const long onePer = PeriodSeconds(per);
    double   barLow  = iLow( sym,per,shift),   barHigh = iHigh(sym,per,shift);
    double   b2High  = iHigh(sym,per,shift+2), b2Low   = iLow( sym,per,shift+2);
    datetime barTime = iTime(sym,per,shift);
    double bullGap = barLow - b2High, bearGap = b2Low - barHigh;
    g_newFvgThisBar = false;
    if(bullGap > 0 && (bullGap/InpPipValue) >= InpFvgMinSize) { BlockAdd(barTime,barLow,b2High,barHigh,barLow,true);  g_newFvgThisBar=true; }
    if(bearGap > 0 && (bearGap/InpPipValue) >= InpFvgMinSize) { BlockAdd(barTime,b2Low,barHigh,barHigh,barLow,false); g_newFvgThisBar=true; }
    g_activeIdx = -1;
    int n = ArraySize(g_blocks);
    for(int i = n-1; i >= 0; i--)
    {
        if(g_blocks[i].startTime < barTime)
        {
            g_blocks[i].blockHigh = MathMax(g_blocks[i].blockHigh, barHigh);
            g_blocks[i].blockLow  = MathMin(g_blocks[i].blockLow,  barLow);
            if(!g_blocks[i].isFilled)
            {
                if( g_blocks[i].isBull && barLow  <= g_blocks[i].gapBottom) g_blocks[i].isFilled = true;
                if(!g_blocks[i].isBull && barHigh >= g_blocks[i].gapTop)    g_blocks[i].isFilled = true;
            }
        }
        if(!g_blocks[i].isFilled && g_activeIdx < 0) g_activeIdx = i;
    }
    if(g_activeIdx < 0) return;
    double abH = g_blocks[g_activeIdx].blockHigh, abL = g_blocks[g_activeIdx].blockLow;
    if(((abH-abL)/InpPipValue) < InpBlkMinSize) return;
    double zs = (abH-abL)*(InpZonePercent/100.0);
    double tb = abH-zs, bb = abL+zs;
    if(g_activeSince != g_blocks[g_activeIdx].startTime)
    {
        g_activeSince = g_blocks[g_activeIdx].startTime;
        g_botRefLow=abL; g_botRefHigh=bb; g_botExtLow=abL; g_botCreateTime=barTime; g_botUnstable=false;
        g_topRefLow=tb;  g_topRefHigh=abH; g_topExtHigh=abH; g_topCreateTime=barTime; g_topUnstable=false;
    }
    else
    {
        if(barLow < g_botExtLow) {
            if((barLow+zs) >= g_botRefLow) g_botExtLow=barLow;
            else { g_botRefLow=barLow; g_botRefHigh=barLow+zs; g_botExtLow=barLow; g_botCreateTime=barTime; g_botUnstable=false; }
        } else if(barLow <= bb && barTime > g_botCreateTime+onePer) g_botUnstable=true;
        if(barHigh > g_topExtHigh) {
            if((barHigh-zs) <= g_topRefHigh) g_topExtHigh=barHigh;
            else { g_topRefLow=barHigh-zs; g_topRefHigh=barHigh; g_topExtHigh=barHigh; g_topCreateTime=barTime; g_topUnstable=false; }
        } else if(barHigh >= tb && barTime > g_topCreateTime+onePer) g_topUnstable=true;
    }
}
// Sum of floating P&L (profit + swap) for all open EA positions on this symbol.
double GetFloatingPnL()
{
    double pnl = 0;
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL)  != Symbol())       continue;
        if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
        pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
    }
    return pnl;
}
// Sum of realised P&L (profit + commission + swap) for closed EA trades since local midnight.
double GetDailyProfit()
{
    // Seconds elapsed since local midnight — used to find server time at local 00:00
    MqlDateTime localDt;
    TimeToStruct(TimeCurrent() + (datetime)((InpUtcOffset - InpServerOffset) * 3600), localDt);
    int secSinceMidnight = localDt.hour * 3600 + localDt.min * 60 + localDt.sec;
    datetime dayStart    = TimeCurrent() - (datetime)secSinceMidnight;

    if(!HistorySelect(dayStart, TimeCurrent() + 1)) return 0;
    double profit = 0;
    int total = HistoryDealsTotal();
    for(int i = 0; i < total; i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetString(ticket,  DEAL_SYMBOL)  != Symbol())           continue;
        if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;
        if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
        profit += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                + HistoryDealGetDouble(ticket, DEAL_SWAP);
    }
    return profit;
}
//+------------------------------------------------------------------+
void ManageTrade()
{
    if(!g_initialized || g_activeIdx < 0) return;
    // Reset recovery mode at the start of each trading window
    if(IsTradingAllowed() && !IsForceCloseTime())
        g_noNewCycles = false;
    int sellPos  = CountPositions(POSITION_TYPE_SELL);
    int buyPos   = CountPositions(POSITION_TYPE_BUY);
    int sellPend = CountPending(ORDER_TYPE_SELL_LIMIT);
    int buyPend  = CountPending(ORDER_TYPE_BUY_LIMIT);
    // ----------------------------------------------------------------
    // HOUSEKEEPING — before the size guard.
    // ----------------------------------------------------------------
    datetime curBlockTime = g_blocks[g_activeIdx].startTime;
    if(curBlockTime != g_prevBlockTime)
    {
        DeleteAllPending(ORDER_TYPE_SELL_LIMIT);
        DeleteAllPending(ORDER_TYPE_BUY_LIMIT);
        g_tpFrozen      = false;
        g_prevBlockTime = curBlockTime;
        sellPend = 0;
        buyPend  = 0;
    }
    if(g_newFvgThisBar)
    {
        if(sellPos == 0 && buyPos == 0)
        {
            DeleteAllPending(ORDER_TYPE_SELL_LIMIT);
            DeleteAllPending(ORDER_TYPE_BUY_LIMIT);
            sellPend = 0;
            buyPend  = 0;
        }
        else
        {
            g_tpFrozen = true;
        }
        g_newFvgThisBar = false;
    }
    if(!IsTradingAllowed() || IsNewsTime())
    {
        if(sellPend > 0 || buyPend > 0)
        {
            DeleteAllPending(ORDER_TYPE_SELL_LIMIT);
            DeleteAllPending(ORDER_TYPE_BUY_LIMIT);
            sellPend = 0;
            buyPend  = 0;
        }
    }
    // ----------------------------------------------------------------
    // FORCE CLOSE — 20:45 onwards
    // ----------------------------------------------------------------
    if(IsForceCloseTime())
    {
        // Always cancel pending orders — no new entries after trading stops
        if(sellPend > 0 || buyPend > 0)
        {
            DeleteAllPending(ORDER_TYPE_SELL_LIMIT);
            DeleteAllPending(ORDER_TYPE_BUY_LIMIT);
            sellPend = 0; buyPend = 0;
        }
        double dayProfit = GetDailyProfit();
        double floatPnL  = GetFloatingPnL();
        if(dayProfit + floatPnL > 0)
        {
            // Net positive day: close everything and rest
            CloseAllPositions();
            g_tpFrozen    = false;
            g_noNewCycles = false;
            return;
        }
        // Net negative: let scale-ins continue to recover; block new cycles
        g_noNewCycles = true;
        // Fall through to state machine — scale-ins may still fire
    }
    // ----------------------------------------------------------------
    // SIZE GUARD
    // ----------------------------------------------------------------
    double abH = g_blocks[g_activeIdx].blockHigh;
    double abL = g_blocks[g_activeIdx].blockLow;
    if(((abH-abL)/InpPipValue) < InpBlkMinSize) return;
    double zs      = (abH-abL)*(InpZonePercent/100.0);
    double topBand = abH-zs, botBand = abL+zs;
    double midPrice= (abH+abL)/2.0;
    double midTop  = midPrice+zs;
    double midBot  = midPrice-zs;
    double dist    = InpMinOrderDistance * InpPipValue;
    int    digits  = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    double ask     = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid     = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    // --- State machine ---
    if(sellPos > 0)
    {
        DeleteAllPending(ORDER_TYPE_BUY_LIMIT);
        if(g_state != STATE_SELLS) g_tpFrozen = false;
        g_state = STATE_SELLS;
    }
    else if(buyPos > 0)
    {
        DeleteAllPending(ORDER_TYPE_SELL_LIMIT);
        if(g_state != STATE_BUYS) g_tpFrozen = false;
        g_state = STATE_BUYS;
    }
    else if(sellPend > 0 || buyPend > 0) g_state = STATE_PENDING;
    else                                 { g_state = STATE_IDLE; g_tpFrozen = false; }
    // ---------------------------------------------------------------
    if(g_state == STATE_IDLE)
    {
        if(IsTradingAllowed() && !IsNewsTime() && !g_noNewCycles)
        {
            // Lot recommendation check — warn if InpInitialLots is below
            // the formula-recommended value for the current account balance.
            double recLots = RecommendedLots();
            if(InpInitialLots < recLots)
                PrintFormat("AVISO: Lote atual %.2f < recomendado %.2f para saldo %.2f. Considere aumentar InpInitialLots.",
                    InpInitialLots, recLots, AccountInfoDouble(ACCOUNT_BALANCE));
            // Sell side: limit if price hasn't reached the zone yet,
            // market order if it has (limit placement would be rejected).
            // Fresh CountPositions guards against the race condition where a
            // SellLimit fill is not yet reflected in the positions pool,
            // which would cause a duplicate market Sell on the same tick.
            if(sellPend == 0)
            {
                if(topBand > ask)
                    g_trade.SellLimit(InpInitialLots, topBand, Symbol(), 0, midTop, ORDER_TIME_GTC, 0, "FVG_SL");
                else if(CountPositions(POSITION_TYPE_SELL) == 0)
                    g_trade.Sell(InpInitialLots, NULL, 0.0, 0.0, midTop, "FVG_SM");
            }
            // Buy side: same logic.
            if(buyPend == 0)
            {
                if(botBand < bid)
                    g_trade.BuyLimit(InpInitialLots, botBand, Symbol(), 0, midBot, ORDER_TIME_GTC, 0, "FVG_BL");
                else if(CountPositions(POSITION_TYPE_BUY) == 0)
                    g_trade.Buy(InpInitialLots, NULL, 0.0, 0.0, midBot, "FVG_BM");
            }
        }
    }
    else if(g_state == STATE_PENDING)
    {
        // For each pending limit: if the recalculated price is still a valid
        // limit price, update it normally.  If the block has grown so that the
        // entry zone is already inside the current market, the limit can no
        // longer sit there — cancel it and enter at market instead.
        if(sellPend > 0)
        {
            if(topBand > ask)
            {
                if(!g_tpFrozen) UpdatePendingOrder(ORDER_TYPE_SELL_LIMIT, topBand, midTop);
            }
            else
            {
                // Sell zone breached — swap limit for market order.
                // Re-check positions in case the limit just filled this tick.
                DeleteAllPending(ORDER_TYPE_SELL_LIMIT);
                if(CountPositions(POSITION_TYPE_SELL) == 0)
                    g_trade.Sell(InpInitialLots, NULL, 0.0, 0.0, midTop, "FVG_SM");
            }
        }
        if(buyPend > 0)
        {
            if(botBand < bid)
            {
                if(!g_tpFrozen) UpdatePendingOrder(ORDER_TYPE_BUY_LIMIT, botBand, midBot);
            }
            else
            {
                // Buy zone breached — swap limit for market order.
                // Re-check positions in case the limit just filled this tick.
                DeleteAllPending(ORDER_TYPE_BUY_LIMIT);
                if(CountPositions(POSITION_TYPE_BUY) == 0)
                    g_trade.Buy(InpInitialLots, NULL, 0.0, 0.0, midBot, "FVG_BM");
            }
        }
    }
    else if(g_state == STATE_SELLS)
    {
        if(!g_tpFrozen)
        {
            double firstEntry = GetFirstPositionEntry(POSITION_TYPE_SELL);
            if(firstEntry > 0 && midTop > firstEntry)
            {
                double be = GetWeightedBreakEven(POSITION_TYPE_SELL);
                UpdateAllTPs(POSITION_TYPE_SELL, NormalizeDouble(be - InpCostPerLot, digits));
                g_tpFrozen = true;
            }
            else
            {
                UpdateAllTPs(POSITION_TYPE_SELL, midTop);
                if(sellPend > 0 && topBand > ask)
                    UpdatePendingOrder(ORDER_TYPE_SELL_LIMIT, topBand, midTop);
            }
        }
        if((IsTradingAllowed() || g_noNewCycles) && !IsNewsTime())
        {
            double lastPrice=0, lastLots=0; datetime lastTime=0;
            if(GetLastPosition(POSITION_TYPE_SELL, lastPrice, lastLots, lastTime))
            {
                if(ask >= lastPrice + dist)
                {
                    double newLots  = NormalizeDouble(lastLots * 2.0, 2);
                    double totalVol = GetTotalVolume(POSITION_TYPE_SELL);
                    double curBE    = GetWeightedBreakEven(POSITION_TYPE_SELL);
                    double newBE    = NormalizeDouble((curBE*totalVol + bid*newLots)/(totalVol+newLots), digits);
                    double newBECost = NormalizeDouble(newBE - InpCostPerLot, digits);
                    if(g_trade.Sell(newLots, NULL, 0.0, 0.0, newBECost, "FVG_SS"))
                    {
                        UpdateAllTPs(POSITION_TYPE_SELL, newBECost);
                        g_tpFrozen = false;
                    }
                }
            }
        }
    }
    else if(g_state == STATE_BUYS)
    {
        if(!g_tpFrozen)
        {
            double firstEntry = GetFirstPositionEntry(POSITION_TYPE_BUY);
            if(firstEntry > 0 && midBot < firstEntry)
            {
                double be = GetWeightedBreakEven(POSITION_TYPE_BUY);
                UpdateAllTPs(POSITION_TYPE_BUY, NormalizeDouble(be + InpCostPerLot, digits));
                g_tpFrozen = true;
            }
            else
            {
                UpdateAllTPs(POSITION_TYPE_BUY, midBot);
                if(buyPend > 0 && botBand < bid)
                    UpdatePendingOrder(ORDER_TYPE_BUY_LIMIT, botBand, midBot);
            }
        }
        if((IsTradingAllowed() || g_noNewCycles) && !IsNewsTime())  // allow scale-in during recovery
        {
            double lastPrice=0, lastLots=0; datetime lastTime=0;
            if(GetLastPosition(POSITION_TYPE_BUY, lastPrice, lastLots, lastTime))
            {
                if(bid <= lastPrice - dist)
                {
                    double newLots  = NormalizeDouble(lastLots * 2.0, 2);
                    double totalVol = GetTotalVolume(POSITION_TYPE_BUY);
                    double curBE    = GetWeightedBreakEven(POSITION_TYPE_BUY);
                    double newBE    = NormalizeDouble((curBE*totalVol + ask*newLots)/(totalVol+newLots), digits);
                    double newBECost = NormalizeDouble(newBE + InpCostPerLot, digits);
                    if(g_trade.Buy(newLots, NULL, 0.0, 0.0, newBECost, "FVG_BS"))
                    {
                        UpdateAllTPs(POSITION_TYPE_BUY, newBECost);
                        g_tpFrozen = false;
                    }
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
void UpdateVisuals()
{
    if(g_activeIdx < 0)
    {
        DeleteAllBoxes();
        g_activeSince=0; g_botUnstable=g_topUnstable=false;
        ChartRedraw(0); return;
    }
    double   bH = g_blocks[g_activeIdx].blockHigh;
    double   bL = g_blocks[g_activeIdx].blockLow;
    datetime bS = g_blocks[g_activeIdx].startTime;
    if(bS < iTime(Symbol(), Period(), 0))
    {
        bH = MathMax(bH, iHigh(Symbol(), Period(), 0));
        bL = MathMin(bL, iLow(Symbol(), Period(), 0));
    }
    bool   valid = ((bH-bL)/InpPipValue) >= InpBlkMinSize;
    double zs    = (bH-bL)*(InpZonePercent/100.0);
    double tb=bH-zs, bb=bL+zs, mid=(bH+bL)/2.0;
    double pips  = (bH-bL) / InpPipValue;
    datetime rTime = iTime(Symbol(),Period(),0) + (datetime)(InpBarsFuture*PeriodSeconds(Period()));
    color cBody, cBorder, cTop, cBot, cMid, cLabel;
    if(valid)
    {
        cBody   = InpCMidBody;
        cBorder = InpCBorder;
        cTop    = g_topUnstable ? InpCUnstable : InpCExtreme;
        cBot    = g_botUnstable ? InpCUnstable : InpCExtreme;
        cMid    = InpCExtreme;
        cLabel  = InpCBorder;
    }
    else
    {
        cBody   = InpCBelowMin;
        cBorder = clrDimGray;
        cTop    = InpCBelowMin;
        cBot    = InpCBelowMin;
        cMid    = InpCBelowMin;
        cLabel  = clrDimGray;
    }
    BoxSet(N_MID,  bS,bH,     rTime,bL,    cBody,  true,  0);
    BoxSet(N_TOP,  bS,bH,     rTime,tb,    cTop,   true,  0);
    BoxSet(N_BOT,  bS,bb,     rTime,bL,    cBot,   true,  0);
    BoxSet(N_MBAND,bS,mid+zs, rTime,mid-zs,cMid,   true,  0);
    BoxSet(N_MID_B,bS,bH,     rTime,bL,    cBorder,false, InpBorderWidth);
    // On-chart size label above the top border
    string sizeText = valid
        ? StringFormat("%.1f pips", pips)
        : StringFormat("%.1f / %.0f pips", pips, InpBlkMinSize);
    if(ObjectFind(0, N_SIZE) < 0)
        ObjectCreate(0, N_SIZE, OBJ_TEXT, 0, bS, bH);
    ObjectSetString (0, N_SIZE, OBJPROP_TEXT,       sizeText);
    ObjectSetInteger(0, N_SIZE, OBJPROP_TIME,    0, bS);
    ObjectSetDouble (0, N_SIZE, OBJPROP_PRICE,   0, bH);
    ObjectSetInteger(0, N_SIZE, OBJPROP_FONTSIZE,   10);
    ObjectSetInteger(0, N_SIZE, OBJPROP_COLOR,      cLabel);
    ObjectSetInteger(0, N_SIZE, OBJPROP_ANCHOR,     ANCHOR_LEFT_LOWER);
    ObjectSetInteger(0, N_SIZE, OBJPROP_BACK,       false);
    ObjectSetInteger(0, N_SIZE, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, N_SIZE, OBJPROP_HIDDEN,     true);
    // Corner info label
    string infoText = valid
        ? StringFormat("Box  %.2f – %.2f  [ %.1f pips ]", bH, bL, pips)
        : StringFormat("Box  %.2f – %.2f  [ %.1f / %.0f pips ]", bH, bL, pips, InpBlkMinSize);
    if(ObjectFind(0, N_INFO) < 0)
        ObjectCreate(0, N_INFO, OBJ_LABEL, 0, 0, 0);
    ObjectSetString (0, N_INFO, OBJPROP_TEXT,       infoText);
    ObjectSetInteger(0, N_INFO, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
    ObjectSetInteger(0, N_INFO, OBJPROP_XDISTANCE,  8);
    ObjectSetInteger(0, N_INFO, OBJPROP_YDISTANCE,  20);
    ObjectSetInteger(0, N_INFO, OBJPROP_FONTSIZE,   10);
    ObjectSetInteger(0, N_INFO, OBJPROP_COLOR,      cLabel);
    ObjectSetInteger(0, N_INFO, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, N_INFO, OBJPROP_HIDDEN,     true);
    // Lot recommendation label (second line, YDISTANCE=40)
    double recLots = RecommendedLots();
    bool   lotOk   = (InpInitialLots >= recLots);
    string lotText = lotOk
        ? StringFormat("Lote: %.2f  OK", InpInitialLots)
        : StringFormat("Lote: %.2f  →  sugerido: %.2f", InpInitialLots, recLots);
    color  lotColor = lotOk ? cLabel : clrOrange;
    if(ObjectFind(0, N_LOTW) < 0)
        ObjectCreate(0, N_LOTW, OBJ_LABEL, 0, 0, 0);
    ObjectSetString (0, N_LOTW, OBJPROP_TEXT,      lotText);
    ObjectSetInteger(0, N_LOTW, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
    ObjectSetInteger(0, N_LOTW, OBJPROP_XDISTANCE, 8);
    ObjectSetInteger(0, N_LOTW, OBJPROP_YDISTANCE, 40);
    ObjectSetInteger(0, N_LOTW, OBJPROP_FONTSIZE,  10);
    ObjectSetInteger(0, N_LOTW, OBJPROP_COLOR,     lotColor);
    ObjectSetInteger(0, N_LOTW, OBJPROP_SELECTABLE,false);
    ObjectSetInteger(0, N_LOTW, OBJPROP_HIDDEN,    true);
    ChartRedraw(0);
}
//+------------------------------------------------------------------+
int OnInit()
{
    ObjectsDeleteAll(0, N_PFX);
    ArrayResize(g_blocks, 0);
    g_activeIdx=g_initialized=false; g_activeSince=0;
    g_botUnstable=g_topUnstable=false;
    g_state=STATE_IDLE; g_tpFrozen=false; g_noNewCycles=false; g_prevBlockTime=0;
    g_trade.SetExpertMagicNumber(InpMagicNumber);
    int total = iBars(Symbol(), Period());
    for(int shift = total-3; shift >= 1; shift--)
        ProcessBar(shift);
    UpdateVisuals();
    g_lastBarTime = iTime(Symbol(), Period(), 0);
    g_initialized = true;
    return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { ObjectsDeleteAll(0, N_PFX); }
void OnTick()
{
    datetime t0 = iTime(Symbol(), Period(), 0);
    if(t0 != g_lastBarTime)
    {
        g_lastBarTime = t0;
        ProcessBar(1);
    }
    UpdateVisuals();
    ManageTrade();
}