//+------------------------------------------------------------------+
//|  AurumBlock.mq5                                                  |
//|  Copyright (c) 2025-2026, Jonathas Costa                         |
//|  github.com/jonathas/trading-bots                                |
//|                                                                  |
//|  MIT License - free to use and modify, keeping this              |
//|  header and copyright notice in all copies.                      |
//+------------------------------------------------------------------+
#property copyright "Jonathas Costa"
#property link      "https://github.com/jonathas/trading-bots"

#property version   "1.03"
#include <Trade\Trade.mqh>

//=== External input ===================================================
input double InpFixedLots = 0.0;   // Fixed lot size (0 = auto by balance)

//=== Strategy constants (compile-time only) ===========================
#define FVG_MIN_SIZE        0.0
#define BLK_MIN_SIZE        39.0
#define ZONE_PCT            5.0
#define PIP_VALUE           0.10
#define BARS_FUTURE         50
// Initial lot: controlled by InpFixedLots input (see GetLots() below).
#define MIN_ORDER_DIST      130.0
#define COST_PER_LOT        0.06        // Round-trip cost per 0.01 lot ($)
#define MAGIC_NUMBER        20250528

//=== Time filter (local UTC+1 summer) ===============================
#define TRADE_START_H       23
#define TRADE_START_M       15          // 15 min after Sydney opens (~23:00)
#define TRADE_STOP_H        19
#define TRADE_STOP_M        45
#define FORCE_CLOSE_H       20
#define FORCE_CLOSE_M       45
#define SERVER_OFFSET       3           // Broker server UTC offset (UTC+3)
#define LOCAL_OFFSET        1           // Local UTC offset (UTC+1)

//=== Session-open pause windows (local UTC+1) =======================
#define PAUSE_WINDOW_MIN    15          // ±minutes around each session open
#define TOKYO_H             1
#define TOKYO_M             0
#define LONDON_H            8
#define LONDON_M            0
#define NYFOREX_H           13          // NY Forex opens 13:00 UTC+1
#define NYFOREX_M           0
#define NYSE_H              14          // NYSE opens 14:30 UTC+1
#define NYSE_M              30

//=== News filter ====================================================
#define NEWS_PRE_SEC        8100        // 135 min before → no new entries
#define NEWS_POST_SEC       900         //  15 min after  → resume
#define NEWS_FILE           "fvg_news.csv"

//=== Web-panel pause flag (shared with the Flask control panel) =====
#define PAUSE_FILE          "fvg_pause.flag"

//=== Style (pre-blended on white background, frosted-glass layered blues) =====
// Formula: out = orig × opacity + 255 × (1 − opacity)
// Base colour: cobalt  R=50  G=100  B=210
//   C_MIDBODY  15% → R=224  G=232  B=247   (lightest — full body fill)
//   C_EXTREME  30% → R=194  G=209  B=242   (top & bottom zone bands)
//   C_MIDBAND  45% → R=163  G=185  B=237   (centre 10% accent band)
//   C_BORDER        → R=50   G=100  B=210   (solid cobalt outline + labels)
//   C_UNSTABLE 40% amber → R=240  G=214  B=153  (yellow-orange warning)
//   C_BELOWMIN      → R=210  G=212  B=218   (neutral grey when block too small)
#define C_MIDBODY           C'224,232,247'
#define C_EXTREME           C'194,209,242'
#define C_MIDBAND           C'163,185,237'
#define C_UNSTABLE          C'240,214,153'
#define C_BELOWMIN          C'210,212,218'
#define C_BORDER            C'50,100,210'
#define BORDER_WIDTH        1

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
bool     g_noNewCycles   = false;
datetime g_prevBlockTime = 0;
datetime g_newsEvents[];                 // loaded from NEWS_FILE (UTC)
string   g_newsNames[];                  // parallel array — event names
int      g_newsCount     = 0;
int      g_lastLoadDay   = -1;           // local day-of-year of last news reload

//=== Object names ===================================================
#define N_MID    "AUR_MID"
#define N_MID_B  "AUR_MID_BORD"
#define N_TOP    "AUR_TOP"
#define N_BOT    "AUR_BOT"
#define N_MBAND  "AUR_MBAND"
#define N_INFO   "AUR_INFO"
#define N_SIZE   "AUR_SIZE"
#define N_DASHBG "AUR_DASH_BG"
#define N_DASH1  "AUR_DASH_1"
#define N_DASH2  "AUR_DASH_2"
#define N_DASH3  "AUR_DASH_3"
#define N_DASH4  "AUR_DASH_4"
#define N_PFX    "AUR_"

//+------------------------------------------------------------------+
//|  News calendar — load from external CSV (FILE_COMMON)            |
//|  Path: %APPDATA%\MetaQuotes\Terminal\Common\Files\fvg_news.csv   |
//|  Format per line: YYYY.MM.DD HH:MM,EventName   (times in UTC)    |
//|  Lines starting with '#' or shorter than 16 chars are ignored.   |
//+------------------------------------------------------------------+
void LoadNewsFile()
{
    int fh = FileOpen(NEWS_FILE, FILE_READ | FILE_ANSI | FILE_COMMON | FILE_TXT);
    if(fh == INVALID_HANDLE)
    {
        PrintFormat("AurumBlock: news file '%s' not found in Common\\Files — news filter inactive.", NEWS_FILE);
        ArrayResize(g_newsEvents, 0);
        ArrayResize(g_newsNames,  0);
        g_newsCount = 0;
        return;
    }
    ArrayResize(g_newsEvents, 0);
    ArrayResize(g_newsNames,  0);
    g_newsCount = 0;
    while(!FileIsEnding(fh))
    {
        string line = FileReadString(fh);
        StringTrimLeft(line);
        StringTrimRight(line);
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
    PrintFormat("AurumBlock: loaded %d news events from %s.", g_newsCount, NEWS_FILE);
}

//+------------------------------------------------------------------+
//|  Diagnostic: print next N upcoming events in local (UTC+1) time. |
//|  Compare the printed times directly against Forex Factory to     |
//|  confirm the UTC→local conversion is working correctly.          |
//+------------------------------------------------------------------+
void PrintUpcomingNews(int maxEvents = 5)
{
    datetime now_utc = TimeCurrent() - (datetime)(SERVER_OFFSET * 3600);
    int shown = 0;
    Print("AurumBlock [NEWS-DIAG] upcoming events (UTC+1 local):");
    for(int i = 0; i < g_newsCount && shown < maxEvents; i++)
    {
        if(g_newsEvents[i] <= now_utc) continue;   // skip past events
        datetime local = g_newsEvents[i] + (datetime)(LOCAL_OFFSET * 3600);
        long minsUntil = ((long)g_newsEvents[i] - (long)now_utc) / 60;
        PrintFormat("  [%d] %s UTC+1 | in %dh%02dm | %s",
            shown + 1,
            TimeToString(local, TIME_DATE | TIME_MINUTES),
            minsUntil / 60, minsUntil % 60,
            g_newsNames[i]);
        shown++;
    }
    if(shown == 0) Print("  (no upcoming events found in CSV)");
}

//+------------------------------------------------------------------+
//|  Sync the MT5 native economic calendar INTO the CSV (live only). |
//|                                                                  |
//|  The CSV is the single source of truth read by LoadNewsFile().   |
//|  Running live, the EA feeds it: it pulls USD high-impact events  |
//|  from the broker calendar and merges any new ones into the file  |
//|  (dedup by timestamp, never deletes history, keeps it sorted).   |
//|  Over time the file accumulates real event times so backtests on |
//|  recent dates reproduce the same blocks — no manual entry.       |
//|                                                                  |
//|  Calendar event times come in broker/server time → −SERVER_OFFSET|
//|  normalises them to UTC, matching the CSV convention.            |
//+------------------------------------------------------------------+
void SyncCalendarToFile()
{
    string keys[];   // "YYYY.MM.DD HH:MM"
    string names[];
    string header[];
    int cnt = 0, hc = 0;

    // 1. Read existing CSV (preserve comments + dedup existing rows)
    int fh = FileOpen(NEWS_FILE, FILE_READ | FILE_ANSI | FILE_COMMON | FILE_TXT);
    if(fh != INVALID_HANDLE)
    {
        while(!FileIsEnding(fh))
        {
            string line = FileReadString(fh);
            StringTrimLeft(line); StringTrimRight(line);
            if(StringLen(line) == 0) continue;
            if(StringGetCharacter(line, 0) == '#')
            { ArrayResize(header, hc+1); header[hc++] = line; continue; }
            if(StringLen(line) < 16) continue;
            string key = StringSubstr(line, 0, 16);
            string nm  = (StringLen(line) > 17) ? StringSubstr(line, 17) : "";
            bool dup = false;
            for(int j = 0; j < cnt; j++) if(keys[j] == key) { dup = true; break; }
            if(dup) continue;
            ArrayResize(keys, cnt+1); ArrayResize(names, cnt+1);
            keys[cnt] = key; names[cnt] = nm; cnt++;
        }
        FileClose(fh);
    }

    // 2. Pull native calendar, merge only XAUUSD-relevant USD events.
    //    The broker classifies many medium-impact events as HIGH, so we use a
    //    whitelist of event-name keywords that actually move gold significantly.
    //    Matching is case-insensitive substring search.
    string WHITELIST[] = {
        // Labour market (red)
        "nonfarm payroll", "non farm payroll", "non-farm payroll", "nfp",
        "average hourly earnings",
        "unemployment rate",
        "adp nonfarm", "adp non-farm", "adp employment",
        // Labour market (orange)
        "unemployment claims", "jobless claims",
        "jolts", "job openings",
        // Inflation (red)
        "cpi", "consumer price",
        "ppi", "producer price",
        "pce", "personal consumption",
        // Growth (red)
        "gdp", "gross domestic product",
        "durable goods",
        "retail sales",
        // Activity (red + orange)
        "ism manufacturing", "ism non-manufacturing", "ism services",
        // Fed (red + orange)
        "fomc", "fed rate", "federal funds", "monetary policy",
        "fed interest rate", "interest rate decision",
        "powell", "fed chair", "fed member", "fomc member"
    };
    datetime from = TimeCurrent() - (datetime)(35 * 86400);   // ~last month
    datetime to   = TimeCurrent() + (datetime)(10 * 86400);   // ~next 10 days
    MqlCalendarValue values[];
    int n = CalendarValueHistory(values, from, to, NULL, "USD");
    int added = 0;
    for(int i = 0; i < n; i++)
    {
        MqlCalendarEvent ev;
        if(!CalendarEventById(values[i].event_id, ev)) continue;
        if(ev.importance != CALENDAR_IMPORTANCE_HIGH &&
           ev.importance != CALENDAR_IMPORTANCE_MODERATE) continue;   // red + orange
        if(values[i].time <= 0)                        continue;
        // Whitelist filter — skip events that don't significantly move gold
        string evLower = ev.name;
        StringToLower(evLower);
        bool relevant = false;
        int wn = ArraySize(WHITELIST);
        for(int w = 0; w < wn && !relevant; w++)
            if(StringFind(evLower, WHITELIST[w]) >= 0) relevant = true;
        if(!relevant) continue;
        // MqlCalendarValue.time is in broker SERVER time — subtract SERVER_OFFSET to get UTC.
        // Confirmed 2026.06.03: events came in UTC+3 (server), 3h ahead of true UTC.
        datetime utc = values[i].time - (datetime)(SERVER_OFFSET * 3600);
        string key = TimeToString(utc, TIME_DATE | TIME_MINUTES);  // "YYYY.MM.DD HH:MM"
        bool dup = false;
        for(int j = 0; j < cnt; j++) if(keys[j] == key) { dup = true; break; }
        if(dup) continue;
        ArrayResize(keys, cnt+1); ArrayResize(names, cnt+1);
        keys[cnt] = key; names[cnt] = ev.name; cnt++; added++;
    }

    if(added == 0 && hc > 0)
    {
        PrintFormat("AurumBlock: news file up to date (%d events).", cnt);
        return;                       // nothing new and file exists → no rewrite
    }

    // 3. Sort chronologically (fixed-width date string sorts == chronological)
    for(int a = 0; a < cnt-1; a++)
        for(int b = a+1; b < cnt; b++)
            if(keys[b] < keys[a])
            {
                string tk = keys[a]; keys[a] = keys[b]; keys[b] = tk;
                string tn = names[a]; names[a] = names[b]; names[b] = tn;
            }

    // 4. Rewrite file (header comments preserved)
    int wh = FileOpen(NEWS_FILE, FILE_WRITE | FILE_ANSI | FILE_COMMON | FILE_TXT);
    if(wh == INVALID_HANDLE) { Print("AurumBlock: cannot write news file."); return; }
    if(hc > 0) for(int i = 0; i < hc; i++) FileWrite(wh, header[i]);
    else
    {
        FileWrite(wh, "# AurumBlock - High-impact USD events for XAUUSD (UTC times)");
        FileWrite(wh, "# Format: YYYY.MM.DD HH:MM,EventName  |  auto-fed from MT5 calendar");
    }
    for(int i = 0; i < cnt; i++) FileWrite(wh, keys[i] + "," + names[i]);
    FileClose(wh);
    PrintFormat("AurumBlock: news file synced (+%d new, %d total).", added, cnt);
}

//+------------------------------------------------------------------+
//|  Load news. CSV is the single source of truth (live + backtest).|
//|  Live runs feed the CSV from the native calendar first.         |
//+------------------------------------------------------------------+
void LoadNews()
{
    if(!(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)))
        SyncCalendarToFile();   // live: refresh CSV from broker calendar
    LoadNewsFile();             // always read the CSV
    PrintUpcomingNews(5);       // print next 5 events in local time → compare with FF
}

//+------------------------------------------------------------------+
//|  Time helpers                                                    |
//+------------------------------------------------------------------+
datetime LocalNow()
{
    return TimeCurrent() + (datetime)((LOCAL_OFFSET - SERVER_OFFSET) * 3600);
}

bool IsTradingAllowed()
{
    MqlDateTime dt;
    TimeToStruct(LocalNow(), dt);
    int current = dt.hour * 60 + dt.min;
    int start   = TRADE_START_H * 60 + TRADE_START_M;
    int stop    = TRADE_STOP_H  * 60 + TRADE_STOP_M;
    if(start == stop) return true;
    if(start < stop)
        return (current >= start && current < stop);
    return (current >= start || current < stop);   // overnight window
}

// Asymmetric news block: [event − 135 min, event + 15 min] (UTC events).
bool IsNewsTime()
{
    datetime now = TimeCurrent() - (datetime)(SERVER_OFFSET * 3600);   // UTC
    for(int i = 0; i < g_newsCount; i++)
    {
        long diff = (long)now - (long)g_newsEvents[i];
        if(diff >= -(long)NEWS_PRE_SEC && diff <= (long)NEWS_POST_SEC) return true;
    }
    return false;
}

// True when |current − sessionOpen| <= window minutes (handles midnight wrap).
bool IsNearOpen(int current, int sessionOpen, int window)
{
    int diff = current - sessionOpen;
    if(diff >  720) diff -= 1440;
    if(diff < -720) diff += 1440;
    return (MathAbs(diff) <= window);
}

// True inside the ±PAUSE_WINDOW_MIN window around any session open.
// Blocks new entries / pending limits; existing positions stay open.
bool IsSessionPauseTime()
{
    MqlDateTime dt;
    TimeToStruct(LocalNow(), dt);
    int current = dt.hour * 60 + dt.min;
    int w = PAUSE_WINDOW_MIN;
    if(IsNearOpen(current, TOKYO_H   * 60 + TOKYO_M,   w)) return true;
    if(IsNearOpen(current, LONDON_H  * 60 + LONDON_M,  w)) return true;
    if(IsNearOpen(current, NYFOREX_H * 60 + NYFOREX_M, w)) return true;
    if(IsNearOpen(current, NYSE_H    * 60 + NYSE_M,    w)) return true;
    return false;
}

// True from FORCE_CLOSE until trading restarts — covers 20:45 → 23:15.
bool IsForceCloseTime()
{
    MqlDateTime dt;
    TimeToStruct(LocalNow(), dt);
    int current = dt.hour * 60 + dt.min;
    int force   = FORCE_CLOSE_H * 60 + FORCE_CLOSE_M;
    int start   = TRADE_START_H * 60 + TRADE_START_M;
    if(force == start) return false;
    if(force < start)
        return (current >= force && current < start);
    return (current >= force || current < start);   // overnight window
}

// True when the web panel has created the pause flag file (FILE_COMMON).
bool IsPaused()
{
    return FileIsExist(PAUSE_FILE, FILE_COMMON);
}

//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL)  != Symbol())     continue;
        if(PositionGetInteger(POSITION_MAGIC)  != MAGIC_NUMBER) continue;
        g_trade.PositionClose(t);
    }
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
    BoxDel(N_BOT); BoxDel(N_MBAND); BoxDel(N_INFO); BoxDel(N_SIZE);
}

//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
{
    int c = 0;
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL)   != Symbol())       continue;
        if(PositionGetInteger(POSITION_MAGIC)   != MAGIC_NUMBER)   continue;
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
        if(OrderGetString(ORDER_SYMBOL)  != Symbol())     continue;
        if(OrderGetInteger(ORDER_MAGIC)  != MAGIC_NUMBER) continue;
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
        if(OrderGetString(ORDER_SYMBOL)  != Symbol())     continue;
        if(OrderGetInteger(ORDER_MAGIC)  != MAGIC_NUMBER) continue;
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
        if(PositionGetString(POSITION_SYMBOL)  != Symbol())     continue;
        if(PositionGetInteger(POSITION_MAGIC)  != MAGIC_NUMBER) continue;
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
        if(PositionGetString(POSITION_SYMBOL)  != Symbol())     continue;
        if(PositionGetInteger(POSITION_MAGIC)  != MAGIC_NUMBER) continue;
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
        if(PositionGetString(POSITION_SYMBOL)  != Symbol())     continue;
        if(PositionGetInteger(POSITION_MAGIC)  != MAGIC_NUMBER) continue;
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
        if(PositionGetString(POSITION_SYMBOL)  != Symbol())     continue;
        if(PositionGetInteger(POSITION_MAGIC)  != MAGIC_NUMBER) continue;
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
        if(PositionGetString(POSITION_SYMBOL)  != Symbol())     continue;
        if(PositionGetInteger(POSITION_MAGIC)  != MAGIC_NUMBER) continue;
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
    if(bullGap > 0 && (bullGap/PIP_VALUE) >= FVG_MIN_SIZE) { BlockAdd(barTime,barLow,b2High,barHigh,barLow,true);  g_newFvgThisBar=true; }
    if(bearGap > 0 && (bearGap/PIP_VALUE) >= FVG_MIN_SIZE) { BlockAdd(barTime,b2Low,barHigh,barHigh,barLow,false); g_newFvgThisBar=true; }
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
    if(((abH-abL)/PIP_VALUE) < BLK_MIN_SIZE) return;
    double zs = (abH-abL)*(ZONE_PCT/100.0);
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

// Floating P&L (profit + swap) for all open EA positions on this symbol.
double GetFloatingPnL()
{
    double pnl = 0;
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL)  != Symbol())     continue;
        if(PositionGetInteger(POSITION_MAGIC)  != MAGIC_NUMBER) continue;
        pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
    }
    return pnl;
}

// Local midnight expressed in server time.
datetime LocalDayStart()
{
    MqlDateTime d;
    TimeToStruct(LocalNow(), d);
    int sec = d.hour * 3600 + d.min * 60 + d.sec;
    return TimeCurrent() - (datetime)sec;
}

// Local Monday 00:00 expressed in server time.
datetime LocalWeekStart()
{
    MqlDateTime d;
    TimeToStruct(LocalNow(), d);
    int dow = d.day_of_week;            // 0 = Sunday … 6 = Saturday
    int daysSinceMon = (dow == 0) ? 6 : (dow - 1);
    int sec = d.hour * 3600 + d.min * 60 + d.sec + daysSinceMon * 86400;
    return TimeCurrent() - (datetime)sec;
}

// Realised P&L (profit + commission + swap) for closed EA trades since local midnight.
double GetDailyProfit()
{
    datetime dayStart = LocalDayStart();
    if(!HistorySelect(dayStart, TimeCurrent() + 1)) return 0;
    double profit = 0;
    int total = HistoryDealsTotal();
    for(int i = 0; i < total; i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetString(ticket,  DEAL_SYMBOL)  != Symbol())          continue;
        if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MAGIC_NUMBER)  continue;
        if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
        profit += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                + HistoryDealGetDouble(ticket, DEAL_SWAP);
    }
    return profit;
}

// Returns the initial lot size for a new cycle entry.
// If FIXED_LOTS > 0: uses that constant.
// Otherwise: auto-scales with balance — ROUND((Balance-400)/800)/100 + 0.01
//   $400 → 0.01 | $1200 → 0.02 | $2000 → 0.03 …  (minimum 0.01)
double GetLots()
{
    if(InpFixedLots > 0.0) return InpFixedLots;
    double bal = AccountInfoDouble(ACCOUNT_BALANCE);
    double rec = MathRound((bal - 400.0) / 800.0) / 100.0 + 0.01;
    return NormalizeDouble(MathMax(rec, 0.01), 2);
}

//+------------------------------------------------------------------+
//|  ManageTrade                                                     |
//+------------------------------------------------------------------+
void ManageTrade()
{
    if(!g_initialized || g_activeIdx < 0) return;
    if(IsPaused()) return;
    if(IsTradingAllowed() && !IsForceCloseTime())
        g_noNewCycles = false;

    int sellPos  = CountPositions(POSITION_TYPE_SELL);
    int buyPos   = CountPositions(POSITION_TYPE_BUY);
    int sellPend = CountPending(ORDER_TYPE_SELL_LIMIT);
    int buyPend  = CountPending(ORDER_TYPE_BUY_LIMIT);

    // HOUSEKEEPING
    datetime curBlockTime = g_blocks[g_activeIdx].startTime;
    if(curBlockTime != g_prevBlockTime)
    {
        DeleteAllPending(ORDER_TYPE_SELL_LIMIT);
        DeleteAllPending(ORDER_TYPE_BUY_LIMIT);
        g_tpFrozen      = false;
        g_prevBlockTime = curBlockTime;
        sellPend = 0; buyPend = 0;
    }
    if(g_newFvgThisBar)
    {
        if(sellPos == 0 && buyPos == 0)
        {
            DeleteAllPending(ORDER_TYPE_SELL_LIMIT);
            DeleteAllPending(ORDER_TYPE_BUY_LIMIT);
            sellPend = 0; buyPend = 0;
        }
        else g_tpFrozen = true;
        g_newFvgThisBar = false;
    }
    // Cancel pending limits when trading is closed, in news window, or session pause
    if(!IsTradingAllowed() || IsNewsTime() || IsSessionPauseTime())
    {
        if(sellPend > 0 || buyPend > 0)
        {
            DeleteAllPending(ORDER_TYPE_SELL_LIMIT);
            DeleteAllPending(ORDER_TYPE_BUY_LIMIT);
            sellPend = 0; buyPend = 0;
        }
    }
    // FORCE CLOSE — 20:45 onwards
    if(IsForceCloseTime())
    {
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
            CloseAllPositions();
            g_tpFrozen    = false;
            g_noNewCycles = false;
            return;
        }
        g_noNewCycles = true;   // net negative: allow scale-ins, block new cycles
    }
    // SIZE GUARD
    double abH = g_blocks[g_activeIdx].blockHigh;
    double abL = g_blocks[g_activeIdx].blockLow;
    if(((abH-abL)/PIP_VALUE) < BLK_MIN_SIZE) return;
    double zs      = (abH-abL)*(ZONE_PCT/100.0);
    double topBand = abH-zs, botBand = abL+zs;
    double midPrice= (abH+abL)/2.0;
    double midTop  = midPrice+zs;
    double midBot  = midPrice-zs;
    double dist    = MIN_ORDER_DIST * PIP_VALUE;
    int    digits  = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    double ask     = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid     = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    // State machine selection
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

    bool canOpen = IsTradingAllowed() && !IsNewsTime() && !IsSessionPauseTime() && !g_noNewCycles;

    if(g_state == STATE_IDLE)
    {
        if(canOpen)
        {
            if(sellPend == 0 && CountPositions(POSITION_TYPE_SELL) == 0)
            {
                if(topBand > ask)
                {
                    if(!g_trade.SellLimit(GetLots(), topBand, Symbol(), 0, midTop, ORDER_TIME_GTC, 0, "AUR_SL"))
                        g_trade.Sell(GetLots(), NULL, 0.0, 0.0, midTop, "AUR_SM");
                }
                else
                    g_trade.Sell(GetLots(), NULL, 0.0, 0.0, midTop, "AUR_SM");
            }
            if(buyPend == 0 && CountPositions(POSITION_TYPE_BUY) == 0)
            {
                if(botBand < bid)
                {
                    if(!g_trade.BuyLimit(GetLots(), botBand, Symbol(), 0, midBot, ORDER_TIME_GTC, 0, "AUR_BL"))
                        g_trade.Buy(GetLots(), NULL, 0.0, 0.0, midBot, "AUR_BM");
                }
                else
                    g_trade.Buy(GetLots(), NULL, 0.0, 0.0, midBot, "AUR_BM");
            }
        }
    }
    else if(g_state == STATE_PENDING)
    {
        if(sellPend > 0)
        {
            if(topBand > ask && !g_tpFrozen)
                UpdatePendingOrder(ORDER_TYPE_SELL_LIMIT, topBand, midTop);
        }
        if(buyPend > 0)
        {
            if(botBand < bid && !g_tpFrozen)
                UpdatePendingOrder(ORDER_TYPE_BUY_LIMIT, botBand, midBot);
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
                UpdateAllTPs(POSITION_TYPE_SELL, NormalizeDouble(be - COST_PER_LOT, digits));
                g_tpFrozen = true;
            }
            else
            {
                UpdateAllTPs(POSITION_TYPE_SELL, midTop);
                if(sellPend > 0 && topBand > ask)
                    UpdatePendingOrder(ORDER_TYPE_SELL_LIMIT, topBand, midTop);
            }
        }
        if((IsTradingAllowed() || g_noNewCycles) && !IsNewsTime() && !IsSessionPauseTime())
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
                    double newBECost = NormalizeDouble(newBE - COST_PER_LOT, digits);
                    if(g_trade.Sell(newLots, NULL, 0.0, 0.0, newBECost, "AUR_SS"))
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
                UpdateAllTPs(POSITION_TYPE_BUY, NormalizeDouble(be + COST_PER_LOT, digits));
                g_tpFrozen = true;
            }
            else
            {
                UpdateAllTPs(POSITION_TYPE_BUY, midBot);
                if(buyPend > 0 && botBand < bid)
                    UpdatePendingOrder(ORDER_TYPE_BUY_LIMIT, botBand, midBot);
            }
        }
        if((IsTradingAllowed() || g_noNewCycles) && !IsNewsTime() && !IsSessionPauseTime())
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
                    double newBECost = NormalizeDouble(newBE + COST_PER_LOT, digits);
                    if(g_trade.Buy(newLots, NULL, 0.0, 0.0, newBECost, "AUR_BS"))
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
//|  Dashboard                                                       |
//+------------------------------------------------------------------+
void DashLabel(const string name, int yoff, const string text, color clr)
{
    if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_LOWER);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_LEFT_LOWER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  20);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  yoff);
    ObjectSetString (0, name, OBJPROP_FONT,       "Consolas");
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   9);
    ObjectSetString (0, name, OBJPROP_TEXT,       text);
    ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

void UpdateDashboard()
{
    datetime weekStart = LocalWeekStart();
    datetime dayStart  = LocalDayStart();

    int  ciclosToday = 0, ciclosWeek = 0;
    int  beCycles = 0, aboveCycles = 0;
    long minSec = -1, maxSec = 0, sumSec = 0;
    int  durN = 0;

    if(HistorySelect(weekStart, TimeCurrent() + 1))
    {
        int total = HistoryDealsTotal();

        // arrays for position duration tracking
        long     posId[];
        datetime posOpen[];
        datetime posClose[];
        int pc = 0;

        // arrays for cycle grouping (EXIT deals)
        datetime exitTime[];
        double   exitNet[];
        int      exitDir[];   // +1 = buy-exit (closing sell), -1 = sell-exit (closing buy)
        int ec = 0;

        for(int i = 0; i < total; i++)
        {
            ulong tk = HistoryDealGetTicket(i);
            if(HistoryDealGetString(tk, DEAL_SYMBOL) != Symbol())           continue;
            if((long)HistoryDealGetInteger(tk, DEAL_MAGIC) != MAGIC_NUMBER) continue;

            ENUM_DEAL_ENTRY deEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk, DEAL_ENTRY);
            ENUM_DEAL_TYPE  deType  = (ENUM_DEAL_TYPE) HistoryDealGetInteger(tk, DEAL_TYPE);
            long     pid = (long)HistoryDealGetInteger(tk, DEAL_POSITION_ID);
            datetime dt  = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);

            // find/create position slot
            int idx = -1;
            for(int k = 0; k < pc; k++) if(posId[k] == pid) { idx = k; break; }
            if(idx < 0)
            {
                idx = pc++;
                ArrayResize(posId, pc); ArrayResize(posOpen, pc); ArrayResize(posClose, pc);
                posId[idx] = pid; posOpen[idx] = 0; posClose[idx] = 0;
            }

            if(deEntry == DEAL_ENTRY_IN)
            {
                if(posOpen[idx] == 0) posOpen[idx] = dt;
                // Count only initial cycle entries — scale-ins use comments AUR_SS / AUR_BS
                string cmt = HistoryDealGetString(tk, DEAL_COMMENT);
                if(StringFind(cmt, "AUR_SS") < 0 && StringFind(cmt, "AUR_BS") < 0)
                {
                    ciclosWeek++;
                    if(dt >= dayStart) ciclosToday++;
                }
            }
            else if(deEntry == DEAL_ENTRY_OUT)
            {
                posClose[idx] = dt;
                double net = HistoryDealGetDouble(tk, DEAL_PROFIT)
                           + HistoryDealGetDouble(tk, DEAL_COMMISSION)
                           + HistoryDealGetDouble(tk, DEAL_SWAP);
                int dir = (deType == DEAL_TYPE_BUY) ? 1 : -1;
                ArrayResize(exitTime, ec+1);
                ArrayResize(exitNet,  ec+1);
                ArrayResize(exitDir,  ec+1);
                exitTime[ec] = dt; exitNet[ec] = net; exitDir[ec] = dir; ec++;
            }
        }

        // ── Cycle grouping ──────────────────────────────────────
        // Group EXIT deals of the same direction within 30 seconds.
        // A martingale cycle may have multiple positions closing near-simultaneously;
        // 30 s is generous enough to catch them without merging unrelated trades.
        if(ec > 0)
        {
            double   curNet = exitNet[0];
            datetime lastT  = exitTime[0];
            int      lastD  = exitDir[0];
            for(int i = 1; i < ec; i++)
            {
                if(exitDir[i] == lastD && (long)(exitTime[i] - lastT) <= 30)
                { curNet += exitNet[i]; lastT = exitTime[i]; }
                else
                {
                    if(curNet > 0.10) aboveCycles++; else beCycles++;
                    curNet = exitNet[i]; lastT = exitTime[i]; lastD = exitDir[i];
                }
            }
            if(curNet > 0.10) aboveCycles++; else beCycles++;
        }

        // ── Position durations (first entry → last close) ───────
        for(int k = 0; k < pc; k++)
        {
            if(posOpen[k] > 0 && posClose[k] > posOpen[k])
            {
                long s = (long)(posClose[k] - posOpen[k]);
                sumSec += s; durN++;
                if(minSec < 0 || s < minSec) minSec = s;
                if(s > maxSec) maxSec = s;
            }
        }
    }

    // ── Format durations ─────────────────────────────────────────
    string sMin, sAvg, sMax;
    if(minSec < 0)
        sMin = "--";
    else if(minSec < 3600)
        sMin = StringFormat("%dm", (int)(minSec/60));
    else
        sMin = StringFormat("%dh%02dm", (int)(minSec/3600), (int)(minSec%3600)/60);

    long avgSec = (durN > 0) ? (sumSec / durN) : 0;
    if(avgSec < 3600)
        sAvg = StringFormat("%dm", (int)(avgSec/60));
    else
        sAvg = StringFormat("%dh%02dm", (int)(avgSec/3600), (int)(avgSec%3600)/60);

    if(maxSec < 3600)
        sMax = StringFormat("%dm", (int)(maxSec/60));
    else
        sMax = StringFormat("%dh%02dm", (int)(maxSec/3600), (int)(maxSec%3600)/60);

    // ── Background panel ─────────────────────────────────────────
    // Solid dark card — readable on any chart background (light or dark).
    if(ObjectFind(0, N_DASHBG) < 0) ObjectCreate(0, N_DASHBG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, N_DASHBG, OBJPROP_CORNER,      CORNER_LEFT_LOWER);
    ObjectSetInteger(0, N_DASHBG, OBJPROP_ANCHOR,      ANCHOR_LEFT_LOWER);
    ObjectSetInteger(0, N_DASHBG, OBJPROP_XDISTANCE,   10);
    ObjectSetInteger(0, N_DASHBG, OBJPROP_YDISTANCE,   10);
    ObjectSetInteger(0, N_DASHBG, OBJPROP_XSIZE,       295);
    ObjectSetInteger(0, N_DASHBG, OBJPROP_YSIZE,       106);
    ObjectSetInteger(0, N_DASHBG, OBJPROP_BGCOLOR,     C'22,27,40');   // deep navy
    ObjectSetInteger(0, N_DASHBG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, N_DASHBG, OBJPROP_COLOR,       C'55,80,135'); // cobalt border
    ObjectSetInteger(0, N_DASHBG, OBJPROP_BACK,        false);
    ObjectSetInteger(0, N_DASHBG, OBJPROP_SELECTABLE,  false);
    ObjectSetInteger(0, N_DASHBG, OBJPROP_HIDDEN,      true);

    // ── Text lines (bottom-up) ───────────────────────────────────
    // Colours: amber-gold title | steel-blue stats | green positive
    color cGold  = C'210,165,50';    // amber gold — readable on dark navy
    color cStat  = C'160,180,210';   // steel blue — secondary stats
    color cGreen = C'75,200,120';    // emerald — above breakeven
    color cDim   = C'100,120,155';   // dimmed — breakeven (neutral)

    DashLabel(N_DASH1, 90,
        StringFormat("Ciclos  hoje: %d    semana: %d", ciclosToday, ciclosWeek),
        cGold);
    DashLabel(N_DASH2, 66,
        StringFormat("Tempo   %s / %s / %s  (min/avg/max)", sMin, sAvg, sMax),
        cStat);
    DashLabel(N_DASH3, 42,
        StringFormat("Breakeven   %d ciclos", beCycles),
        cDim);
    DashLabel(N_DASH4, 18,
        StringFormat("Acima BE    %d ciclos", aboveCycles),
        cGreen);
}

//+------------------------------------------------------------------+
void UpdateVisuals()
{
    if(g_activeIdx < 0)
    {
        DeleteAllBoxes();
        g_activeSince=0; g_botUnstable=g_topUnstable=false;
        UpdateDashboard();
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
    bool   valid = ((bH-bL)/PIP_VALUE) >= BLK_MIN_SIZE;
    double zs    = (bH-bL)*(ZONE_PCT/100.0);
    double tb=bH-zs, bb=bL+zs, mid=(bH+bL)/2.0;
    double pips  = (bH-bL) / PIP_VALUE;
    datetime rTime = iTime(Symbol(),Period(),0) + (datetime)(BARS_FUTURE*PeriodSeconds(Period()));
    color cBody, cBorder, cTop, cBot, cMid, cLabel;
    if(valid)
    {
        cBody   = C_MIDBODY;
        cBorder = C_BORDER;
        cTop    = g_topUnstable ? C_UNSTABLE : C_EXTREME;
        cBot    = g_botUnstable ? C_UNSTABLE : C_EXTREME;
        cMid    = C_MIDBAND;
        cLabel  = C_BORDER;
    }
    else
    {
        cBody = C_BELOWMIN; cBorder = clrDimGray; cTop = C_BELOWMIN;
        cBot  = C_BELOWMIN; cMid = C_BELOWMIN;    cLabel = clrDimGray;
    }
    BoxSet(N_MID,  bS,bH,     rTime,bL,    cBody,  true,  0);
    BoxSet(N_TOP,  bS,bH,     rTime,tb,    cTop,   true,  0);
    BoxSet(N_BOT,  bS,bb,     rTime,bL,    cBot,   true,  0);
    BoxSet(N_MBAND,bS,mid+zs, rTime,mid-zs,cMid,   true,  0);
    BoxSet(N_MID_B,bS,bH,     rTime,bL,    cBorder,false, BORDER_WIDTH);

    string sizeText = valid
        ? StringFormat("%.1f pips", pips)
        : StringFormat("%.1f / %.0f pips", pips, BLK_MIN_SIZE);
    if(ObjectFind(0, N_SIZE) < 0) ObjectCreate(0, N_SIZE, OBJ_TEXT, 0, bS, bH);
    ObjectSetString (0, N_SIZE, OBJPROP_TEXT,       sizeText);
    ObjectSetInteger(0, N_SIZE, OBJPROP_TIME,    0, bS);
    ObjectSetDouble (0, N_SIZE, OBJPROP_PRICE,   0, bH);
    ObjectSetInteger(0, N_SIZE, OBJPROP_FONTSIZE,   10);
    ObjectSetInteger(0, N_SIZE, OBJPROP_COLOR,      cLabel);
    ObjectSetInteger(0, N_SIZE, OBJPROP_ANCHOR,     ANCHOR_LEFT_LOWER);
    ObjectSetInteger(0, N_SIZE, OBJPROP_BACK,       false);
    ObjectSetInteger(0, N_SIZE, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, N_SIZE, OBJPROP_HIDDEN,     true);

    // Corner info label — status prefix
    bool   paused = IsPaused();
    string boxDesc = valid
        ? StringFormat("Box  %.2f – %.2f  [ %.1f pips ]", bH, bL, pips)
        : StringFormat("Box  %.2f – %.2f  [ %.1f / %.0f pips ]", bH, bL, pips, BLK_MIN_SIZE);
    string status = "";
    color  infoColor = cLabel;
    if(paused)                  { status = "⏸ PAUSED   ";        infoColor = clrRed; }
    else if(IsSessionPauseTime()){ status = "⏸ SESSION PAUSE   "; infoColor = clrYellow; }
    else if(IsNewsTime())       { status = "📰 NEWS BLOCK   ";    infoColor = clrYellow; }
    string infoText = status + boxDesc;
    if(ObjectFind(0, N_INFO) < 0) ObjectCreate(0, N_INFO, OBJ_LABEL, 0, 0, 0);
    ObjectSetString (0, N_INFO, OBJPROP_TEXT,       infoText);
    ObjectSetInteger(0, N_INFO, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
    ObjectSetInteger(0, N_INFO, OBJPROP_XDISTANCE,  8);
    ObjectSetInteger(0, N_INFO, OBJPROP_YDISTANCE,  20);
    ObjectSetInteger(0, N_INFO, OBJPROP_FONTSIZE,   10);
    ObjectSetInteger(0, N_INFO, OBJPROP_COLOR,      infoColor);
    ObjectSetInteger(0, N_INFO, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, N_INFO, OBJPROP_HIDDEN,     true);

    UpdateDashboard();
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
int OnInit()
{
    ObjectsDeleteAll(0, N_PFX);
    ArrayResize(g_blocks, 0);
    g_activeIdx = -1; g_initialized = false; g_activeSince = 0;
    g_botUnstable = g_topUnstable = false;
    g_state = STATE_IDLE; g_tpFrozen = false; g_noNewCycles = false; g_prevBlockTime = 0;
    g_trade.SetExpertMagicNumber(MAGIC_NUMBER);

    LoadNews();
    MqlDateTime d; TimeToStruct(LocalNow(), d); g_lastLoadDay = d.day_of_year;

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
        // Reload news calendar once per local day (picks up weekly updates)
        MqlDateTime d; TimeToStruct(LocalNow(), d);
        if(d.day_of_year != g_lastLoadDay) { LoadNews(); g_lastLoadDay = d.day_of_year; }
    }
    UpdateVisuals();
    ManageTrade();
}
