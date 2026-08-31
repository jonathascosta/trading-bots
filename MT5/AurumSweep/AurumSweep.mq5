//+------------------------------------------------------------------+
//|  AurumSweep.mq5                                                          |
//|  Copyright (c) 2026, Jonathas Costa                              |
//|  github.com/jonathascosta/trading-bots                           |
//|                                                                  |
//|  MIT License - free to use and modify, keeping this              |
//|  header and copyright notice in all copies.                      |
//+------------------------------------------------------------------+
#property copyright "Jonathas Costa"
#property link      "https://github.com/jonathascosta/trading-bots"
#property version   "1.06"
#include <Trade\Trade.mqh>

//=== Inputs =========================================================
input group  "=== Risk ==="
input double InpRiskPct         = 1.25;  // Risk per trade cap (% of balance)
input bool   InpDynamicRisk     = true;  // Scale risk to remaining drawdown cushion
input double InpCushionFrac     = 0.20;  // Risk = this fraction of cushion to the max-loss floor
input double InpRR              = 2.5;   // Reward:risk ratio (fixed-TP mode)
input int    InpExitMode        = 1;     // 0=fixed TP at RR  1=ATR trailing stop (no TP)
input double InpTrailAtr        = 2.0;   // Trail distance (x ATR M15)
input double InpBreakEvenAtR    = 1.0;   // BE move / trail activation at +N*R (0 = off)
input double InpBEOffsetUsd     = 0.30;  // BE offset beyond entry (price units)

input group  "=== Challenge guards ==="
input double InpInitialBalance  = 0.0;   // Challenge initial balance (0 = balance at first run)
input double InpDailyHaltPct    = 2.4;   // Daily loss halt, closes all (% of initial balance)
input double InpMaxHaltPct      = 5.0;   // Permanent halt (% of initial balance)
input double InpTargetLockPct   = 10.2;  // Profit lock: close all + stop (% of initial balance)
input int    InpMaxTradesPerDay = 4;     // Max entries per day

input group  "=== Time (session times are local) ==="
input int    InpServerOffset    = 3;     // Broker server UTC offset (hours)
input int    InpLocalOffset     = 1;     // Local UTC offset (hours)
input int    InpLon1H = 8;               // London window start hour
input int    InpLon1M = 15;              // London window start minute
input int    InpLon2H = 11;              // London window stop hour
input int    InpLon2M = 30;              // London window stop minute
input int    InpNy1H  = 13;              // NY window start hour
input int    InpNy1M  = 15;              // NY window start minute
input int    InpNy2H  = 17;              // NY window stop hour
input int    InpNy2M  = 30;              // NY window stop minute
input int    InpFriCutH = 20;            // Friday close-all hour (local)

input group  "=== Strategy ==="
input int    InpMode           = 1;      // 0=sweep-reversal 1=trend-continuation 2=both
input double InpPullbackAtr    = 2.25;   // Continuation: min pullback depth (x ATR M15)
input int    InpSwingBars      = 48;     // Continuation: rolling extreme lookback (M5 bars)
input bool   InpUsePDHL        = true;   // Sweep levels: previous day high/low
input bool   InpUseAsia        = true;   // Sweep levels: Asian session high/low
input int    InpBiasMode       = 1;      // H1 bias: 0=off 1=soft(allow neutral) 2=strict
input int    InpConfirmBars    = 9;      // Bars after sweep to find FVG confirmation
input int    InpOrderExpiryBars= 18;     // Pending order lifetime (M5 bars)
input bool   InpEntryAtMid     = true;   // Entry at FVG midpoint (false = gap edge)
input double InpMinFvgAtr      = 0.10;   // Min FVG gap size (x ATR M15)
input double InpSLBufAtr       = 0.50;   // SL buffer beyond sweep extreme (x ATR M15)
input double InpMinSLAtr       = 1.00;   // Reject setups with SL closer than this (x ATR M15)
input double InpMaxSLAtr       = 4.00;   // Reject setups with SL wider than this (x ATR M15)
input double InpMaxSpreadPips  = 5.0;    // Max spread to trade (pips)

input group  "=== Filters / Logging ==="
input bool   InpNewsFilter     = true;   // Block entries around red USD news
input bool   InpLogDB          = true;   // SQLite logging (AurumSweep.db)

//=== Constants ======================================================
#define PIP             0.10
#define TF_ENTRY        PERIOD_M5
#define TF_BIAS         PERIOD_H1
#define MAGIC_NUMBER    20260704
#define NEWS_FILE       "fvg_news.csv"
#define DB_FILE         "AurumSweep.db"
#define NEWS_PRE_SEC    3600            // block entries from 60 min before event
#define NEWS_POST_SEC   900             // until 15 min after
#define ASIA_START_H    0               // Asian range window (local)
#define ASIA_STOP_H     7
#define COMMENT_SEC     2               // panel refresh throttle (s)

//=== State ==========================================================
enum ESwState { SW_IDLE, SW_WAIT_CONFIRM, SW_PENDING, SW_IN_TRADE };

struct Setup {
    bool     isLong;
    string   level;        // "PDH" / "PDL" / "AsiaH" / "AsiaL"
    double   extreme;      // sweep bar extreme (SL anchor)
    datetime sweepTime;
    int      barsLeft;     // confirmation window countdown
};

CTrade    g_trade;
ESwState  g_state        = SW_IDLE;
Setup     g_setup;
bool      g_initialized  = false;

// Day levels
double    g_pdh = 0, g_pdl = 0;
double    g_asiaHi = 0, g_asiaLo = 0;
bool      g_sweptPDH = false, g_sweptPDL = false;
bool      g_sweptAsiaH = false, g_sweptAsiaL = false;
long      g_dayStamp = -1;

// H1 bias
int       g_bias = 0;                  // +1 bull / -1 bear / 0 neutral
double    g_swingHigh = 0, g_swingLow = 0;
datetime  g_lastH1Bar = 0;

// Guards
double    g_initBal      = 0;
double    g_dayAnchor    = 0;
bool      g_dailyHalt    = false;
bool      g_permHalt     = false;
bool      g_targetLock   = false;
int       g_tradesToday  = 0;

// Trade tracking
double    g_openRisk     = 0;          // |entry - sl| of live position
bool      g_beDone       = false;
datetime  g_fillTime     = 0;
long      g_dbTradeId    = 0;

// News
datetime  g_newsEvents[];
string    g_newsNames[];
int       g_newsCount    = 0;
int       g_lastLoadDay  = -1;

// Misc
datetime  g_lastM5Bar    = 0;
datetime  g_lastComment  = 0;
int       g_db           = INVALID_HANDLE;
int       g_atrHandle    = INVALID_HANDLE;

// Volatility unit: ATR(14) on M15, refreshed once per M5 bar
double CurrentATR()
{
    static double atr = 0;
    static datetime lastBar = 0;
    datetime bt = iTime(_Symbol, TF_ENTRY, 0);
    if(bt != lastBar && g_atrHandle != INVALID_HANDLE)
    {
        double buf[1];
        if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) == 1 && buf[0] > 0) { atr = buf[0]; lastBar = bt; }
    }
    return atr;
}

//+------------------------------------------------------------------+
//|  Time helpers                                                    |
//+------------------------------------------------------------------+
datetime LocalNow()               { return TimeCurrent() + (datetime)((InpLocalOffset - InpServerOffset) * 3600); }
datetime ToLocal(datetime server) { return server + (datetime)((InpLocalOffset - InpServerOffset) * 3600); }

bool InTradeWindow()
{
    MqlDateTime dt; TimeToStruct(LocalNow(), dt);
    int cur = dt.hour * 60 + dt.min;
    int l1 = InpLon1H * 60 + InpLon1M, l2 = InpLon2H * 60 + InpLon2M;
    int n1 = InpNy1H  * 60 + InpNy1M,  n2 = InpNy2H  * 60 + InpNy2M;
    return (cur >= l1 && cur < l2) || (cur >= n1 && cur < n2);
}

bool IsFridayCutoff()
{
    MqlDateTime dt; TimeToStruct(LocalNow(), dt);
    return (dt.day_of_week == 5 && dt.hour >= InpFriCutH);
}

//+------------------------------------------------------------------+
//|  News filter (CSV in Common\Files, UTC times)                    |
//+------------------------------------------------------------------+
void LoadNewsFile()
{
    int fh = FileOpen(NEWS_FILE, FILE_READ | FILE_ANSI | FILE_COMMON | FILE_TXT);
    ArrayResize(g_newsEvents, 0);
    ArrayResize(g_newsNames,  0);
    g_newsCount = 0;
    if(fh == INVALID_HANDLE)
    {
        Print("AurumSweep: news file not found - news filter inactive.");
        return;
    }
    while(!FileIsEnding(fh))
    {
        string line = FileReadString(fh);
        StringTrimLeft(line); StringTrimRight(line);
        if(StringLen(line) < 16)               continue;
        if(StringGetCharacter(line, 0) == '#') continue;
        datetime dt = StringToTime(StringSubstr(line, 0, 16));
        if(dt <= 0) continue;
        string nm = (StringLen(line) > 17) ? StringSubstr(line, 17) : "";
        ArrayResize(g_newsEvents, g_newsCount + 1);
        ArrayResize(g_newsNames,  g_newsCount + 1);
        g_newsEvents[g_newsCount] = dt;
        g_newsNames [g_newsCount] = nm;
        g_newsCount++;
    }
    FileClose(fh);
    Print("AurumSweep: loaded " + IntegerToString(g_newsCount) + " news events.");
}

bool IsNewsBlock()
{
    if(!InpNewsFilter || g_newsCount == 0) return false;
    datetime now = TimeCurrent() - (datetime)(InpServerOffset * 3600);   // UTC
    for(int i = 0; i < g_newsCount; i++)
    {
        long diff = (long)now - (long)g_newsEvents[i];
        if(diff >= -(long)NEWS_PRE_SEC && diff <= (long)NEWS_POST_SEC) return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//|  SQLite logging                                                  |
//+------------------------------------------------------------------+
string DBEsc(const string s) { string r = s; StringReplace(r, "'", "''"); return r; }

void DBInit()
{
    if(!InpLogDB) return;
    g_db = DatabaseOpen(DB_FILE, DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE);
    if(g_db == INVALID_HANDLE) { Print("AurumSweep: cannot open DB."); return; }
    DatabaseExecute(g_db,
        "CREATE TABLE IF NOT EXISTS trades ("
        "id INTEGER PRIMARY KEY, dir TEXT, level TEXT, sweep_time INTEGER, "
        "open_time INTEGER, close_time INTEGER, entry REAL, sl REAL, tp REAL, "
        "lots REAL, pnl REAL, result TEXT);");
    DatabaseExecute(g_db,
        "CREATE TABLE IF NOT EXISTS events ("
        "id INTEGER PRIMARY KEY, t INTEGER, type TEXT, note TEXT);");
}

long DBLastInsertId()
{
    int req = DatabasePrepare(g_db, "SELECT last_insert_rowid();");
    if(req == INVALID_HANDLE) return 0;
    long id = 0;
    if(DatabaseRead(req)) DatabaseColumnLong(req, 0, id);
    DatabaseFinalize(req);
    return id;
}

void DBEvent(const string type, const string note)
{
    if(g_db == INVALID_HANDLE) return;
    DatabaseExecute(g_db, "INSERT INTO events(t,type,note) VALUES(" +
        IntegerToString((long)TimeCurrent()) + ",'" + DBEsc(type) + "','" + DBEsc(note) + "');");
}

void DBTradeOpen(double entry, double sl, double tp, double lots)
{
    if(g_db == INVALID_HANDLE) { g_dbTradeId = 0; return; }
    DatabaseExecute(g_db, "INSERT INTO trades(dir,level,sweep_time,open_time,entry,sl,tp,lots) VALUES('" +
        (g_setup.isLong ? "buy" : "sell") + "','" + DBEsc(g_setup.level) + "'," +
        IntegerToString((long)g_setup.sweepTime) + "," +
        IntegerToString((long)TimeCurrent()) + "," +
        DoubleToString(entry, 2) + "," + DoubleToString(sl, 2) + "," +
        DoubleToString(tp, 2) + "," + DoubleToString(lots, 2) + ");");
    g_dbTradeId = DBLastInsertId();
}

void DBTradeClose(double pnl, const string result)
{
    if(g_db == INVALID_HANDLE || g_dbTradeId <= 0) return;
    DatabaseExecute(g_db, "UPDATE trades SET close_time=" +
        IntegerToString((long)TimeCurrent()) + ", pnl=" + DoubleToString(pnl, 2) +
        ", result='" + DBEsc(result) + "' WHERE id=" + IntegerToString(g_dbTradeId) + ";");
    g_dbTradeId = 0;
}

//+------------------------------------------------------------------+
//|  Position / order helpers                                        |
//+------------------------------------------------------------------+
bool HasPosition()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol())      continue;
        if(PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER)  continue;
        return true;
    }
    return false;
}

ulong GetPendingTicket()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong t = OrderGetTicket(i);
        if(!OrderSelect(t)) continue;
        if(OrderGetString(ORDER_SYMBOL) != Symbol())      continue;
        if(OrderGetInteger(ORDER_MAGIC) != MAGIC_NUMBER)  continue;
        return t;
    }
    return 0;
}

void CancelPending()
{
    ulong t = GetPendingTicket();
    while(t != 0) { g_trade.OrderDelete(t); t = GetPendingTicket(); }
}

void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol())      continue;
        if(PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER)  continue;
        g_trade.PositionClose(t);
    }
}

double SpreadPips() { return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / PIP; }

//+------------------------------------------------------------------+
//|  Day levels: PDH/PDL + Asian range                               |
//+------------------------------------------------------------------+
void UpdateDayLevels()
{
    long today = (long)(LocalNow() / 86400);
    if(today != g_dayStamp)
    {
        g_dayStamp   = today;
        g_pdh        = iHigh(_Symbol, PERIOD_D1, 1);   // server-day aligned (~2h off local; acceptable)
        g_pdl        = iLow (_Symbol, PERIOD_D1, 1);
        g_asiaHi     = 0; g_asiaLo = 0;
        g_sweptPDH   = false; g_sweptPDL   = false;
        g_sweptAsiaH = false; g_sweptAsiaL = false;
        g_tradesToday = 0;
        g_dailyHalt   = false;
        double bal = AccountInfoDouble(ACCOUNT_BALANCE);
        double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
        g_dayAnchor = MathMax(bal, eq);
    }
    // Extend Asian range from the last closed M5 bar
    datetime bt = iTime(_Symbol, TF_ENTRY, 1);
    MqlDateTime dt; TimeToStruct(ToLocal(bt), dt);
    if(dt.hour >= ASIA_START_H && dt.hour < ASIA_STOP_H)
    {
        double h = iHigh(_Symbol, TF_ENTRY, 1), l = iLow(_Symbol, TF_ENTRY, 1);
        if(g_asiaHi == 0 || h > g_asiaHi) g_asiaHi = h;
        if(g_asiaLo == 0 || l < g_asiaLo) g_asiaLo = l;
    }
}

//+------------------------------------------------------------------+
//|  H1 swing-structure bias (fractal 2-2, break by close)           |
//+------------------------------------------------------------------+
void UpdateBias()
{
    datetime t = iTime(_Symbol, TF_BIAS, 0);
    if(t == g_lastH1Bar || t == 0) return;
    g_lastH1Bar = t;
    if(iBars(_Symbol, TF_BIAS) < 7) return;
    int s = 3;   // fractal confirmed 2 bars later
    double h = iHigh(_Symbol, TF_BIAS, s), l = iLow(_Symbol, TF_BIAS, s);
    if(h > iHigh(_Symbol, TF_BIAS, s+1) && h > iHigh(_Symbol, TF_BIAS, s+2) &&
       h >= iHigh(_Symbol, TF_BIAS, s-1) && h >= iHigh(_Symbol, TF_BIAS, s-2))
        g_swingHigh = h;
    if(l < iLow(_Symbol, TF_BIAS, s+1) && l < iLow(_Symbol, TF_BIAS, s+2) &&
       l <= iLow(_Symbol, TF_BIAS, s-1) && l <= iLow(_Symbol, TF_BIAS, s-2))
        g_swingLow = l;
    double c = iClose(_Symbol, TF_BIAS, 1);
    if(g_swingHigh > 0 && c > g_swingHigh) g_bias = +1;
    if(g_swingLow  > 0 && c < g_swingLow)  g_bias = -1;
}

bool BiasAllows(bool isLong)
{
    if(InpBiasMode == 0) return true;
    if(InpBiasMode == 1) return isLong ? (g_bias >= 0) : (g_bias <= 0);
    return isLong ? (g_bias == +1) : (g_bias == -1);
}

//+------------------------------------------------------------------+
//|  Setup detection: sweep of a liquidity level on closed M5 bar    |
//+------------------------------------------------------------------+
bool EntriesBlocked()
{
    return (g_dailyHalt || g_permHalt || g_targetLock || !InTradeWindow() ||
            IsFridayCutoff() || IsNewsBlock() || g_tradesToday >= InpMaxTradesPerDay ||
            HasPosition() || GetPendingTicket() != 0);
}

bool TrySetup(bool isLong, const string level, double barHi, double barLo)
{
    if(EntriesBlocked())        return false;
    if(!BiasAllows(isLong))     return false;
    g_setup.isLong    = isLong;
    g_setup.level     = level;
    g_setup.extreme   = isLong ? barLo : barHi;
    g_setup.sweepTime = iTime(_Symbol, TF_ENTRY, 1);
    g_setup.barsLeft  = InpConfirmBars;
    g_state = SW_WAIT_CONFIRM;
    Print("AurumSweep: sweep of " + level + " -> waiting confirmation (" +
          (isLong ? "long" : "short") + ").");
    return true;
}

void CheckSweeps()
{
    double hi = iHigh(_Symbol, TF_ENTRY, 1);
    double lo = iLow (_Symbol, TF_ENTRY, 1);
    double cl = iClose(_Symbol, TF_ENTRY, 1);
    // Flags burn only when a setup is actually armed, so sweeps that happen
    // while entries are blocked (window/news/bias) keep the level available.
    // Bearish setups: sweep above a high, close back below
    if(InpUsePDHL && !g_sweptPDH && g_pdh > 0 && hi > g_pdh && cl < g_pdh)
        { if(TrySetup(false, "PDH", hi, lo))   { g_sweptPDH   = true; return; } }
    if(InpUseAsia && !g_sweptAsiaH && g_asiaHi > 0 && hi > g_asiaHi && cl < g_asiaHi)
        { if(TrySetup(false, "AsiaH", hi, lo)) { g_sweptAsiaH = true; return; } }
    // Bullish setups: sweep below a low, close back above
    if(InpUsePDHL && !g_sweptPDL && g_pdl > 0 && lo < g_pdl && cl > g_pdl)
        { if(TrySetup(true, "PDL", hi, lo))    { g_sweptPDL   = true; return; } }
    if(InpUseAsia && !g_sweptAsiaL && g_asiaLo > 0 && lo < g_asiaLo && cl > g_asiaLo)
        { if(TrySetup(true, "AsiaL", hi, lo))  { g_sweptAsiaL = true; return; } }
}

//+------------------------------------------------------------------+
//|  Continuation trigger: deep pullback against a strict H1 bias.   |
//|  Same FVG confirmation as sweeps; SL anchors at the pullback     |
//|  extreme, which keeps updating while waiting for the FVG.        |
//+------------------------------------------------------------------+
void CheckPullbacks()
{
    double atr = CurrentATR();
    if(atr <= 0 || g_bias == 0) return;
    double lo1 = iLow(_Symbol, TF_ENTRY, 1), hi1 = iHigh(_Symbol, TF_ENTRY, 1);
    if(g_bias == +1)
    {
        int ih = iHighest(_Symbol, TF_ENTRY, MODE_HIGH, InpSwingBars, 1);
        if(ih < 0) return;
        double rollHigh = iHigh(_Symbol, TF_ENTRY, ih);
        if((rollHigh - lo1) >= InpPullbackAtr * atr)
            TrySetup(true, "PullB", hi1, lo1);
    }
    else
    {
        int il = iLowest(_Symbol, TF_ENTRY, MODE_LOW, InpSwingBars, 1);
        if(il < 0) return;
        double rollLow = iLow(_Symbol, TF_ENTRY, il);
        if((hi1 - rollLow) >= InpPullbackAtr * atr)
            TrySetup(false, "PullS", hi1, lo1);
    }
}

//+------------------------------------------------------------------+
//|  Confirmation: displacement FVG in setup direction               |
//|  Bull FVG: low(1) > high(3); bear FVG: high(1) < low(3)          |
//+------------------------------------------------------------------+
void CheckConfirmation()
{
    double lo1 = iLow (_Symbol, TF_ENTRY, 1), hi1 = iHigh(_Symbol, TF_ENTRY, 1);
    // Continuation setups: SL anchor follows the deepest point of the pullback
    if(StringFind(g_setup.level, "Pull") == 0)
    {
        if(g_setup.isLong)  g_setup.extreme = MathMin(g_setup.extreme, lo1);
        else                g_setup.extreme = MathMax(g_setup.extreme, hi1);
    }
    double lo3 = iLow (_Symbol, TF_ENTRY, 3), hi3 = iHigh(_Symbol, TF_ENTRY, 3);
    double o2  = iOpen(_Symbol, TF_ENTRY, 2), c2  = iClose(_Symbol, TF_ENTRY, 2);
    double entry = 0, gapTop = 0, gapBot = 0;
    double minGap = InpMinFvgAtr * CurrentATR();
    if(minGap <= 0) return;
    bool found = false;
    if(g_setup.isLong && (lo1 - hi3) >= minGap && c2 > o2)
        { gapTop = lo1; gapBot = hi3; found = true; }
    if(!g_setup.isLong && (lo3 - hi1) >= minGap && c2 < o2)
        { gapTop = lo3; gapBot = hi1; found = true; }
    if(found)
    {
        if(InpEntryAtMid) entry = (gapTop + gapBot) / 2.0;
        else              entry = g_setup.isLong ? gapTop : gapBot;   // near edge, fills first
        PlaceEntry(entry);
        return;
    }
    g_setup.barsLeft--;
    if(g_setup.barsLeft <= 0)
    {
        g_state = SW_IDLE;
        Print("AurumSweep: confirmation window expired (" + g_setup.level + ").");
    }
}

//+------------------------------------------------------------------+
//|  Entry placement                                                 |
//+------------------------------------------------------------------+
double CalcLots(double slDist)
{
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    if(tickSize <= 0 || tickVal <= 0) return 0;
    double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0;
    if(InpDynamicRisk)
    {
        // Never bust: bet a fixed fraction of the cushion above the max-loss floor,
        // so position size shrinks toward zero as drawdown approaches the halt level.
        double floorEq  = g_initBal * (1.0 - InpMaxHaltPct / 100.0);
        double cushion  = AccountInfoDouble(ACCOUNT_EQUITY) - floorEq;
        if(cushion <= 0) return 0;
        riskMoney = MathMin(riskMoney, cushion * InpCushionFrac);
    }
    double perLot    = slDist / tickSize * tickVal;      // loss per 1.0 lot at SL
    if(perLot <= 0) return 0;
    double lots = riskMoney / perLot;
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    lots = MathFloor(lots / step) * step;
    if(lots < vmin) return 0;                            // min lot would over-risk
    return MathMin(lots, vmax);
}

void PlaceEntry(double entry)
{
    if(SpreadPips() > InpMaxSpreadPips)
    {
        Print("AurumSweep: spread too wide, setup skipped.");
        g_state = SW_IDLE;
        return;
    }
    double atr = CurrentATR();
    if(atr <= 0) { g_state = SW_IDLE; return; }
    double buf = InpSLBufAtr * atr;
    double sl  = g_setup.isLong ? (g_setup.extreme - buf) : (g_setup.extreme + buf);
    double slDist = MathAbs(entry - sl);
    if(slDist < InpMinSLAtr * atr || slDist > InpMaxSLAtr * atr)
    {
        Print("AurumSweep: SL distance out of bounds (" + DoubleToString(slDist / PIP, 1) +
              " pips vs ATR " + DoubleToString(atr / PIP, 1) + "), skipped.");
        g_state = SW_IDLE;
        return;
    }
    double tp = 0;   // trail mode runs without TP
    if(InpExitMode == 0)
        tp = g_setup.isLong ? (entry + InpRR * slDist) : (entry - InpRR * slDist);
    entry = NormalizeDouble(entry, _Digits);
    sl    = NormalizeDouble(sl,    _Digits);
    tp    = NormalizeDouble(tp,    _Digits);
    double lots = CalcLots(slDist);
    if(lots <= 0)
    {
        Print("AurumSweep: lot calc failed / min lot over-risks, skipped.");
        g_state = SW_IDLE;
        return;
    }
    datetime expiry = TimeCurrent() + (datetime)(InpOrderExpiryBars * PeriodSeconds(TF_ENTRY));
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    bool ok = false;
    if(g_setup.isLong)
    {
        double mtp = (InpExitMode == 0) ? NormalizeDouble(ask + InpRR * (ask - sl), _Digits) : 0;
        if(ask <= entry) ok = g_trade.Buy(lots, _Symbol, 0, sl, mtp, "sweep " + g_setup.level);
        else             ok = g_trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry, "sweep " + g_setup.level);
    }
    else
    {
        double mtp = (InpExitMode == 0) ? NormalizeDouble(bid - InpRR * (sl - bid), _Digits) : 0;
        if(bid >= entry) ok = g_trade.Sell(lots, _Symbol, 0, sl, mtp, "sweep " + g_setup.level);
        else             ok = g_trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry, "sweep " + g_setup.level);
    }
    if(!ok)
    {
        Print("AurumSweep: order send failed: " + IntegerToString(g_trade.ResultRetcode()));
        g_state = SW_IDLE;
        return;
    }
    g_state = SW_PENDING;
    Print("AurumSweep: entry placed " + (g_setup.isLong ? "long" : "short") +
          " @ " + DoubleToString(entry, 2) + " SL " + DoubleToString(sl, 2) +
          " TP " + DoubleToString(tp, 2) + " lots " + DoubleToString(lots, 2));
}

//+------------------------------------------------------------------+
//|  Pending invalidation: price traded through SL before fill       |
//+------------------------------------------------------------------+
void ManagePending()
{
    ulong t = GetPendingTicket();
    if(t == 0) return;
    if(!OrderSelect(t)) return;
    long   type = OrderGetInteger(ORDER_TYPE);
    double osl  = OrderGetDouble(ORDER_SL);
    double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double askp = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if((type == ORDER_TYPE_BUY_LIMIT  && bid  <= osl) ||
       (type == ORDER_TYPE_SELL_LIMIT && askp >= osl))
    {
        g_trade.OrderDelete(t);
        g_state = SW_IDLE;
        Print("AurumSweep: pending invalidated (price hit SL level before fill).");
    }
}

//+------------------------------------------------------------------+
//|  Position management: break-even move                            |
//+------------------------------------------------------------------+
void ManagePosition()
{
    if(InpBreakEvenAtR <= 0 || g_openRisk <= 0) return;
    if(InpExitMode == 0 && g_beDone) return;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol())      continue;
        if(PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER)  continue;
        double entry = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl    = PositionGetDouble(POSITION_SL);
        double tp    = PositionGetDouble(POSITION_TP);
        long   type  = PositionGetInteger(POSITION_TYPE);
        double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double askp  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        bool   isBuy = (type == POSITION_TYPE_BUY);
        double gain  = isBuy ? (bid - entry) : (entry - askp);
        if(gain < InpBreakEvenAtR * g_openRisk) continue;   // not activated yet
        if(InpExitMode == 1)
        {
            // Chandelier trail: SL follows price at InpTrailAtr x ATR, ratchet only
            double dist  = InpTrailAtr * CurrentATR();
            if(dist <= 0) continue;
            double newSL = NormalizeDouble(isBuy ? (bid - dist) : (askp + dist), _Digits);
            bool better  = isBuy ? (newSL > sl + 0.10) : (sl == 0 || newSL < sl - 0.10);
            if(better) g_trade.PositionModify(t, newSL, tp);
        }
        else
        {
            double newSL = NormalizeDouble(isBuy ? (entry + InpBEOffsetUsd) : (entry - InpBEOffsetUsd), _Digits);
            bool better  = isBuy ? (newSL > sl) : (sl == 0 || newSL < sl);
            if(better) g_trade.PositionModify(t, newSL, tp);
            g_beDone = true;
        }
    }
}

//+------------------------------------------------------------------+
//|  Challenge guards                                                |
//+------------------------------------------------------------------+
string GVName(const string tag) { return "ASW_" + tag + "_" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)); }

void HaltAll(const string reason)
{
    CancelPending();
    CloseAllPositions();
    g_state = SW_IDLE;
    DBEvent("halt", reason);
    Print("AurumSweep: HALT - " + reason);
}

void UpdateGuards()
{
    if(g_permHalt || g_targetLock) return;
    double eq = AccountInfoDouble(ACCOUNT_EQUITY);
    // Profit lock: challenge passed, stop touching the account
    if(eq >= g_initBal * (1.0 + InpTargetLockPct / 100.0))
    {
        g_targetLock = true;
        GlobalVariableSet(GVName("LOCK"), 1);
        HaltAll("TARGET REACHED - equity " + DoubleToString(eq, 2));
        return;
    }
    // Permanent halt: protect max drawdown
    if(eq <= g_initBal * (1.0 - InpMaxHaltPct / 100.0))
    {
        g_permHalt = true;
        GlobalVariableSet(GVName("HALT"), 1);
        HaltAll("MAX LOSS GUARD - equity " + DoubleToString(eq, 2));
        return;
    }
    // Daily halt: protect daily drawdown (allowance is % of initial balance)
    if(!g_dailyHalt && (g_dayAnchor - eq) >= g_initBal * InpDailyHaltPct / 100.0)
    {
        g_dailyHalt = true;
        HaltAll("DAILY LOSS GUARD - equity " + DoubleToString(eq, 2));
    }
}

//+------------------------------------------------------------------+
//|  Trade lifecycle tracking                                        |
//+------------------------------------------------------------------+
void TrackLifecycle()
{
    bool hasPos = HasPosition();
    if(g_state == SW_PENDING)
    {
        if(hasPos)
        {
            // Filled: capture R distance from the actual position
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
                ulong t = PositionGetTicket(i);
                if(!PositionSelectByTicket(t)) continue;
                if(PositionGetString(POSITION_SYMBOL) != Symbol())      continue;
                if(PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER)  continue;
                double entry = PositionGetDouble(POSITION_PRICE_OPEN);
                double sl    = PositionGetDouble(POSITION_SL);
                g_openRisk = MathAbs(entry - sl);
                DBTradeOpen(entry, sl, PositionGetDouble(POSITION_TP), PositionGetDouble(POSITION_VOLUME));
                break;
            }
            g_beDone   = false;
            g_fillTime = TimeCurrent();
            g_tradesToday++;
            g_state = SW_IN_TRADE;
        }
        else if(GetPendingTicket() == 0)
            g_state = SW_IDLE;   // expired or cancelled
    }
    else if(g_state == SW_IN_TRADE && !hasPos)
    {
        // Closed: pull result from history
        double pnl = 0;
        string result = "closed";
        if(HistorySelect(g_fillTime - 60, TimeCurrent() + 1))
        {
            for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
            {
                ulong d = HistoryDealGetTicket(i);
                if(HistoryDealGetString(d, DEAL_SYMBOL) != Symbol())                              continue;
                if((long)HistoryDealGetInteger(d, DEAL_MAGIC) != MAGIC_NUMBER)                    continue;
                if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT)       continue;
                pnl = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_SWAP);
                long reason = HistoryDealGetInteger(d, DEAL_REASON);
                if(reason == DEAL_REASON_TP)      result = "tp";
                else if(reason == DEAL_REASON_SL) result = (pnl > 50 ? "trail" : (pnl >= 0 ? "be" : "sl"));
                break;
            }
        }
        DBTradeClose(pnl, result);
        Print("AurumSweep: trade closed (" + result + ") pnl " + DoubleToString(pnl, 2));
        g_openRisk = 0;
        g_state = SW_IDLE;
    }
}

//+------------------------------------------------------------------+
//|  Chart comment panel                                             |
//+------------------------------------------------------------------+
void UpdatePanel()
{
    if(TimeCurrent() - g_lastComment < COMMENT_SEC) return;
    g_lastComment = TimeCurrent();
    double eq = AccountInfoDouble(ACCOUNT_EQUITY);
    string st = "IDLE";
    if(g_state == SW_WAIT_CONFIRM) st = "WAIT_CONFIRM " + g_setup.level + " (" + IntegerToString(g_setup.barsLeft) + ")";
    if(g_state == SW_PENDING)      st = "PENDING " + g_setup.level;
    if(g_state == SW_IN_TRADE)     st = "IN_TRADE " + g_setup.level;
    if(g_dailyHalt)  st = "DAILY HALT";
    if(g_permHalt)   st = "PERMANENT HALT";
    if(g_targetLock) st = "TARGET LOCKED - PASSED";
    string biasStr = (g_bias > 0 ? "BULL" : (g_bias < 0 ? "BEAR" : "NEUTRAL"));
    Comment("AurumSweep v1.06 | " + st +
            "\nBias H1: " + biasStr +
            " | PDH " + DoubleToString(g_pdh, 2) + " PDL " + DoubleToString(g_pdl, 2) +
            " | Asia " + DoubleToString(g_asiaHi, 2) + "/" + DoubleToString(g_asiaLo, 2) +
            "\nEquity " + DoubleToString(eq, 2) +
            " | Day P&L " + DoubleToString(eq - g_dayAnchor, 2) +
            " | Trades today " + IntegerToString(g_tradesToday) + "/" + IntegerToString(InpMaxTradesPerDay) +
            "\nGuards: daily -" + DoubleToString(g_initBal * InpDailyHaltPct / 100.0, 0) +
            " max eq " + DoubleToString(g_initBal * (1.0 - InpMaxHaltPct / 100.0), 0) +
            " target eq " + DoubleToString(g_initBal * (1.0 + InpTargetLockPct / 100.0), 0) +
            (InTradeWindow() ? "" : "\n(outside trade window)") +
            (IsNewsBlock() ? "\n(news block active)" : ""));
}

//+------------------------------------------------------------------+
int OnInit()
{
    g_trade.SetExpertMagicNumber(MAGIC_NUMBER);
    g_trade.SetDeviationInPoints(30);
    g_initBal = (InpInitialBalance > 0) ? InpInitialBalance : AccountInfoDouble(ACCOUNT_BALANCE);
    g_dayAnchor = MathMax(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
    if(GlobalVariableCheck(GVName("HALT"))) g_permHalt   = true;
    if(GlobalVariableCheck(GVName("LOCK"))) g_targetLock = true;
    if(StringFind(_Symbol, "XAU") < 0)
        Print("AurumSweep: WARNING - designed for XAUUSD, running on " + _Symbol);
    g_atrHandle = iATR(_Symbol, PERIOD_M15, 14);
    if(g_atrHandle == INVALID_HANDLE)
    {
        Print("AurumSweep: cannot create ATR handle.");
        return INIT_FAILED;
    }
    LoadNewsFile();
    DBInit();
    g_initialized = true;
    Print("AurumSweep v1.06 initialized. Initial balance " + DoubleToString(g_initBal, 2) +
          (g_permHalt ? " [PERM HALT ACTIVE]" : "") + (g_targetLock ? " [TARGET LOCKED]" : ""));
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Comment("");
    if(g_db != INVALID_HANDLE) DatabaseClose(g_db);
    if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
}

//+------------------------------------------------------------------+
void OnTick()
{
    if(!g_initialized) return;
    UpdateGuards();
    TrackLifecycle();
    UpdatePanel();
    if(g_permHalt || g_targetLock) return;

    if(IsFridayCutoff() && (HasPosition() || GetPendingTicket() != 0))
        HaltAll("Friday cutoff - flat over weekend");

    ManagePending();
    ManagePosition();

    // Bar-driven logic on new M5 bar
    datetime bt = iTime(_Symbol, TF_ENTRY, 0);
    if(bt == g_lastM5Bar || bt == 0) return;
    g_lastM5Bar = bt;

    // Daily news reload (live convenience; tester reads once at init)
    MqlDateTime ld; TimeToStruct(LocalNow(), ld);
    if(ld.day_of_year != g_lastLoadDay)
    {
        g_lastLoadDay = ld.day_of_year;
        if(!(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))) LoadNewsFile();
    }

    UpdateDayLevels();
    UpdateBias();

    if(g_state == SW_IDLE)
    {
        if(InpMode != 1)                     CheckSweeps();
        if(g_state == SW_IDLE && InpMode >= 1) CheckPullbacks();
    }
    else if(g_state == SW_WAIT_CONFIRM)
    {
        CheckConfirmation();
        if(g_state == SW_IDLE && InpMode != 1) CheckSweeps();
    }
}
