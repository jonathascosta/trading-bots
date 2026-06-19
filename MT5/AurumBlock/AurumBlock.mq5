//+------------------------------------------------------------------+
//|  AurumBlock.mq5                                                  |
//|  Copyright (c) 2026, Jonathas Costa                              |
//|  github.com/jonathascosta/trading-bots                           |
//|                                                                  |
//|  MIT License - free to use and modify, keeping this              |
//|  header and copyright notice in all copies.                      |
//+------------------------------------------------------------------+
#property copyright "Jonathas Costa"
#property link      "https://github.com/jonathascosta/trading-bots"
#property version   "1.30"
#define EA_DASH_VER "v1.30"   // shown in dashboard — update together with #property version
#include <Trade\Trade.mqh>

//=== External inputs ==================================================
input double InpFixedLots    = 0.0;    // Fixed lot size (0 = auto by balance)
input double InpMinOrderDist = 130.0;  // Distance between scale-ins (pips)
input double InpLotMultiplier = 2.0;   // Scale-in lot multiplier (2=double, 3=triple…)
input int    InpUIScale      = 1;      // Dashboard scale: 1=normal, 2=Mac HiDPI/Retina

input group  "=== DB Logging ==="
input bool   InpLogTrades    = true;   // log order/position lifecycle
input bool   InpLogBlocks    = true;   // log FVG block and zone touch events
input bool   InpLogFilters   = true;   // log news/session/time filter transitions
input bool   InpLogSnapshots = true;   // log periodic P&L snapshots

//=== Strategy constants (compile-time only) ===========================
#define FVG_MIN_SIZE        0.0
#define BLK_MIN_SIZE        39.0
#define ZONE_PCT            5.0
#define PIP_VALUE           0.10
#define BARS_FUTURE         50
// Initial lot: controlled by InpFixedLots input (see GetLots() below).
#define COST_PER_LOT        0.06        // Round-trip cost per 0.01 lot ($)
#define MAGIC_NUMBER        20250528

//=== Time filter (local UTC+1 summer) ===============================
#define TRADE_START_H       23
#define TRADE_START_M       15          // 15 min after Sydney opens (~23:00)
#define TRADE_STOP_H        19
#define TRADE_STOP_M        45
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
#define NEXT_SESSION_WARN_MIN  60       // show session-pause warning up to X min before it starts
#define NEXT_NEWS_WARN_MIN     90       // amber warning when news pre-block starts in < X min
#define NEXT_NEWS_SHOW_H       8        // show next news event if it occurs within X hours

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
#define C_UNSTABLE          C'240,214,153'  // 2nd touch — amber warning (40% on white)
#define C_OVERTOUCHED       C'255,153,153'  // 3+ touches — red warning  (40% on white)
#define TOUCH_WARN_COUNT    3               // touches to flip to C_OVERTOUCHED
#define C_BELOWMIN          C'210,212,218'
#define C_BORDER            C'50,100,210'

//=== Dashboard panel bitmap =========================================
// True ARGB transparency is only achievable via ResourceCreate + OBJ_BITMAP_LABEL.
// OBJ_RECTANGLE_LABEL ignores the alpha channel in OBJPROP_BGCOLOR on MT5.
#define DASH_PAN_W          370     // panel width  (px)
#define DASH_PAN_H          179     // panel height (px) — 7 rows × 24 px + margins
#define DASH_PAN_BOT        10      // gap between panel bottom and chart bottom (px)
#define DASH_PAN_RES        "::AurBlock_Pan"   // in-memory bitmap resource name
#define DASH_PAN_ALPHA      225     // 0=transparent 255=opaque → 88% opacity

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
int      g_botTouchCount = 0;   // number of distinct visits to the bottom zone
bool     g_botInZone     = false; // true while price is inside the bottom zone (prevents multi-bar double-count)
double   g_topRefLow = 0, g_topRefHigh = 0, g_topExtHigh = 0;
datetime g_topCreateTime = 0;
bool     g_topUnstable   = false;
int      g_topTouchCount = 0;   // number of distinct visits to the top zone
bool     g_topInZone     = false; // true while price is inside the top zone
CTrade   g_trade;
EState   g_state         = STATE_IDLE;
bool     g_tpFrozen      = false;
bool     g_noNewCycles   = false;
datetime g_prevBlockTime = 0;
datetime g_tradeBlockTime = 0;   // startTime of the block that opened the current cycle
datetime g_newsEvents[];                 // loaded from NEWS_FILE (UTC)
string   g_newsNames[];                  // parallel array — event names
int      g_newsCount     = 0;
int      g_lastLoadDay   = -1;           // local day-of-year of last news reload
int      g_panX         = -1;           // dashboard panel left edge (px from chart left)
int      g_panY         = -1;           // dashboard panel top edge  (px from chart top)
bool     g_panDragged   = false;        // true once user has dragged the panel
bool     g_dragging     = false;        // true while left mouse button held over panel
int      g_dragOffX     = 0;           // cursor X offset from panel left at drag start
int      g_dragOffY     = 0;           // cursor Y offset from panel top  at drag start
bool     g_prevLBtn     = false;        // left-button state on previous MOUSE_MOVE event

// DB logging state
int      g_db               = INVALID_HANDLE;
int      g_sessionId        = -1;
int      g_currentBlockId   = -1;
EState   g_prevState        = STATE_IDLE;
datetime g_cycleOpenTime    = 0;
int      g_cycleStartDealCount = 0;
double   g_cyclePeakDD     = 0.0;  // most negative floating P&L seen during current cycle
ulong    g_openTickets[];
int      g_openTicketCount  = 0;
bool     g_prevNews         = false;
bool     g_prevSessionPause = false;
bool     g_prevTradingAllowed = true;
bool     g_prevForceClose   = false;
bool     g_prevWebPause     = false;
datetime g_filterOnTimes[5];           // indexed: 0=news 1=pause 2=trading 3=force 4=web
datetime g_lastSnapshotDate = 0;
int      g_lastArchiveMonth = -1;

//=== Object names ===================================================
#define N_MID    "AUR_MID"
#define N_TOP    "AUR_TOP"
#define N_BOT    "AUR_BOT"
#define N_MBAND  "AUR_MBAND"
#define N_SIZE   "AUR_SIZE"
#define N_DASHBG "AUR_DASH_BG"
#define N_DASH0  "AUR_DASH_0"   // status / state row  (new)
#define N_DASHB  "AUR_DASH_B"   // box info row        (replaces N_INFO)
#define N_DASHN  "AUR_DASH_N"   // next-event preview row
#define N_DASHV  "AUR_DASH_V"   // version label (top-right of panel)
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

    // ── Helper: dedup check by (exact datetime) OR (same date + same name, case-insensitive).
    // When a same-name duplicate is found with a DIFFERENT time, the EARLIER time wins.
    // Returns true if the entry is a duplicate (caller should skip it).
    // On a "same name, later time" conflict the existing entry's key is patched in-place.
    #define CHECK_DUP(newKey, newName) \
    { \
        string _date = StringSubstr(newKey, 0, 10); \
        string _norm = newName; StringToLower(_norm); \
        bool _dup = false; \
        for(int _j = 0; _j < cnt; _j++) \
        { \
            if(keys[_j] == newKey) { _dup = true; break; } \
            string _ed = StringSubstr(keys[_j], 0, 10); \
            string _en = names[_j]; StringToLower(_en); \
            if(_ed == _date && _en == _norm) \
            { \
                if(newKey < keys[_j]) keys[_j] = newKey; \
                _dup = true; break; \
            } \
        } \
        if(_dup) continue; \
    }

    // 1. Read existing CSV (preserve comments; dedup by date+name, keep earlier time)
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
            CHECK_DUP(key, nm)
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
        // Housing (orange) — moves gold via USD rate expectations
        "existing home sales", "new home sales",
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
        CHECK_DUP(key, ev.name)
        ArrayResize(keys, cnt+1); ArrayResize(names, cnt+1);
        keys[cnt] = key; names[cnt] = ev.name; cnt++; added++;
    }

    #undef CHECK_DUP

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

// True from TRADE_STOP (19:45) until trading restarts at TRADE_START (23:15).
bool IsForceCloseTime()
{
    MqlDateTime dt;
    TimeToStruct(LocalNow(), dt);
    int current = dt.hour * 60 + dt.min;
    int force   = TRADE_STOP_H  * 60 + TRADE_STOP_M;
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
    BoxDel(N_MID); BoxDel(N_TOP);
    BoxDel(N_BOT); BoxDel(N_MBAND); BoxDel(N_SIZE);
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
        if(MathAbs(PositionGetDouble(POSITION_TP) - newTP) > 0.01)
            g_trade.PositionModify(t, 0, newTP);
    }
}
void UpdatePendingOrder(ENUM_ORDER_TYPE type, double newPrice, double newTP)
{
    ulong t = GetPendingTicket(type);
    if(t == 0) return;
    if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - newPrice) > 0.01 ||
       MathAbs(OrderGetDouble(ORDER_TP)          - newTP)   > 0.01)
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
        g_botRefLow=abL; g_botRefHigh=bb; g_botExtLow=abL; g_botCreateTime=barTime; g_botUnstable=false; g_botTouchCount=0; g_botInZone=false;
        g_topRefLow=tb;  g_topRefHigh=abH; g_topExtHigh=abH; g_topCreateTime=barTime; g_topUnstable=false; g_topTouchCount=0; g_topInZone=false;
        DBLogBlock(g_blocks[g_activeIdx].isBull, abH, abL, abH, tb, bb, abL, barTime);
    }
    else
    {
        // Bottom zone — count only on entry (false→true transition), not on every in-zone bar.
        if(barLow < g_botExtLow) {
            if((barLow+zs) >= g_botRefLow) g_botExtLow=barLow;
            else { g_botRefLow=barLow; g_botRefHigh=barLow+zs; g_botExtLow=barLow; g_botCreateTime=barTime; g_botUnstable=false; g_botTouchCount=0; g_botInZone=false; }
            g_botInZone = true;   // price is in/below zone; hold flag to avoid double-count next bar
        } else if(barLow <= bb && barTime > g_botCreateTime+onePer) {
            if(!g_botInZone) { g_botUnstable=true; g_botTouchCount++; DBLogZoneTouch("bot", barLow, g_botTouchCount); }
            g_botInZone = true;
        } else { g_botInZone = false; }   // price is above zone — reset for next entry
        // Top zone — same pattern.
        if(barHigh > g_topExtHigh) {
            if((barHigh-zs) <= g_topRefHigh) g_topExtHigh=barHigh;
            else { g_topRefLow=barHigh-zs; g_topRefHigh=barHigh; g_topExtHigh=barHigh; g_topCreateTime=barTime; g_topUnstable=false; g_topTouchCount=0; g_topInZone=false; }
            g_topInZone = true;
        } else if(barHigh >= tb && barTime > g_topCreateTime+onePer) {
            if(!g_topInZone) { g_topUnstable=true; g_topTouchCount++; DBLogZoneTouch("top", barHigh, g_topTouchCount); }
            g_topInZone = true;
        } else { g_topInZone = false; }
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
// If InpFixedLots > 0: uses that value (override).
// Otherwise: 0.01 * MAX(1; 1 + FLOOR((SQRT(2*Balance - 700) - 30) / 20; 1))
//   $400 – 1599  → 0.01  |  $1600 – 2799 → 0.02
//   $2800 – 4399 → 0.03  |  $4400 – 6399 → 0.04  …
double GetLots()
{
    if(InpFixedLots > 0.0) return InpFixedLots;
    double bal = AccountInfoDouble(ACCOUNT_BALANCE);
    double arg = 2.0 * bal - 700.0;
    if(arg <= 0.0) return 0.01;          // balance < $350 → minimum lot
    double step = MathFloor((MathSqrt(arg) - 30.0) / 20.0);
    double lots = 0.01 * MathMax(1.0, 1.0 + step);
    return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//|  DB Logging — SQLite persistence (MQL5\Files\AurumBlock.db)     |
//+------------------------------------------------------------------+

string DBGetActiveNewsName()
{
    datetime nowUtc = TimeCurrent() - (datetime)(SERVER_OFFSET * 3600);
    for(int i = 0; i < g_newsCount; i++)
    {
        long diff = (long)nowUtc - (long)g_newsEvents[i];
        if(diff >= -(long)NEWS_PRE_SEC && diff <= (long)NEWS_POST_SEC)
            return (i < ArraySize(g_newsNames) ? g_newsNames[i] : "");
    }
    return "";
}
string DBGetActivePauseName()
{
    MqlDateTime dt; TimeToStruct(LocalNow(), dt);
    int cur = dt.hour * 60 + dt.min, w = PAUSE_WINDOW_MIN;
    if(IsNearOpen(cur, TOKYO_H  *60+TOKYO_M,   w)) return "Tokyo";
    if(IsNearOpen(cur, LONDON_H *60+LONDON_M,  w)) return "London";
    if(IsNearOpen(cur, NYFOREX_H*60+NYFOREX_M, w)) return "NYForex";
    if(IsNearOpen(cur, NYSE_H   *60+NYSE_M,    w)) return "NYSE";
    return "";
}
bool   IsTesting()            { return (bool)MQLInfoInteger(MQL_TESTER); }
string DBEsc(const string s)  { string r = s; StringReplace(r, "'", "''"); return r; }
long   DBLastInsertId()
{
    int req = DatabasePrepare(g_db, "SELECT last_insert_rowid();");
    if(req == INVALID_HANDLE) return 0;
    long id = 0;
    if(DatabaseRead(req)) DatabaseColumnLong(req, 0, id);
    DatabaseFinalize(req);
    return id;
}

void DBInit()
{
    if(IsTesting()) return;
    g_db = DatabaseOpen("AurumBlock.db", DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE);
    if(g_db == INVALID_HANDLE) { PrintFormat("AurumBlock DB: open failed — error %d", GetLastError()); return; }
    DatabaseExecute(g_db,
        "CREATE TABLE IF NOT EXISTS sessions("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,start_time INTEGER NOT NULL,"
        "stop_time INTEGER,version TEXT,symbol TEXT,account INTEGER,config_json TEXT);");
    DatabaseExecute(g_db,
        "CREATE TABLE IF NOT EXISTS blocks("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,session_id INTEGER,created_at INTEGER NOT NULL,"
        "is_bull INTEGER,block_high REAL,block_low REAL,size_pips REAL,"
        "top_zone_high REAL,top_zone_low REAL,bot_zone_high REAL,bot_zone_low REAL,"
        "invalidated_at INTEGER,invalidated_reason TEXT);");
    DatabaseExecute(g_db,
        "CREATE TABLE IF NOT EXISTS zone_touches("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,block_id INTEGER,session_id INTEGER,"
        "touched_at INTEGER NOT NULL,zone TEXT,touch_count INTEGER,price REAL,exhausted INTEGER);");
    DatabaseExecute(g_db,
        "CREATE TABLE IF NOT EXISTS filter_events("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,session_id INTEGER,event_time INTEGER NOT NULL,"
        "filter_type TEXT,state TEXT,detail TEXT,duration_sec INTEGER);");
    DatabaseExecute(g_db,
        "CREATE TABLE IF NOT EXISTS trades("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,session_id INTEGER,block_id INTEGER,"
        "ticket INTEGER,type TEXT,lots REAL,entry_price REAL,tp REAL,"
        "placed_at INTEGER,filled_at INTEGER,closed_at INTEGER,"
        "close_price REAL,profit REAL,commission REAL,swap REAL,close_reason TEXT);");
    DatabaseExecute(g_db,
        "CREATE TABLE IF NOT EXISTS cycles("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,session_id INTEGER,block_id INTEGER,"
        "direction TEXT,open_time INTEGER,close_time INTEGER,duration_sec INTEGER,"
        "scale_in_count INTEGER,peak_lots REAL,net_pnl REAL,above_be INTEGER,max_dd REAL DEFAULT 0.0);");
    DatabaseExecute(g_db,
        "CREATE TABLE IF NOT EXISTS pnl_snapshots("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,session_id INTEGER,"
        "snapshot_time INTEGER NOT NULL,trigger TEXT,"
        "daily_realized REAL,floating_pnl REAL,open_positions INTEGER,"
        "cycles_today INTEGER,cycles_week INTEGER,be_cycles INTEGER,above_be_cycles INTEGER);");
    // Add max_dd to existing DBs (no-op if column already exists)
    DatabaseExecute(g_db, "ALTER TABLE cycles ADD COLUMN max_dd REAL DEFAULT 0.0;");
    DatabaseExecute(g_db, "CREATE INDEX IF NOT EXISTS idx_blocks_session  ON blocks(session_id);");
    DatabaseExecute(g_db, "CREATE INDEX IF NOT EXISTS idx_touches_block   ON zone_touches(block_id);");
    DatabaseExecute(g_db, "CREATE INDEX IF NOT EXISTS idx_filters_session ON filter_events(session_id,event_time);");
    DatabaseExecute(g_db, "CREATE INDEX IF NOT EXISTS idx_trades_session  ON trades(session_id,placed_at);");
    DatabaseExecute(g_db, "CREATE INDEX IF NOT EXISTS idx_cycles_session  ON cycles(session_id,open_time);");
    DatabaseExecute(g_db, "CREATE INDEX IF NOT EXISTS idx_snapshots_time  ON pnl_snapshots(snapshot_time);");
}

void DBLogSession()
{
    if(g_db == INVALID_HANDLE || IsTesting()) return;
    string cfg = StringFormat(
        "{\"version\":\"%s\",\"symbol\":\"%s\",\"blk_min\":%.1f,"
        "\"zone_pct\":%.1f,\"cost\":%.3f,\"magic\":%d,"
        "\"trade_start\":\"%02d:%02d\",\"trade_stop\":\"%02d:%02d\","
        "\"lot_mult\":%.1f,\"min_dist\":%.1f,\"fixed_lots\":%.2f}",
        EA_DASH_VER, Symbol(), BLK_MIN_SIZE, ZONE_PCT, COST_PER_LOT, MAGIC_NUMBER,
        TRADE_START_H, TRADE_START_M, TRADE_STOP_H, TRADE_STOP_M,
        InpLotMultiplier, InpMinOrderDist, InpFixedLots);
    if(DatabaseExecute(g_db, StringFormat(
        "INSERT INTO sessions(start_time,version,symbol,account,config_json) "
        "VALUES(%d,'%s','%s',%d,'%s');",
        (long)TimeCurrent(), EA_DASH_VER, Symbol(),
        (int)AccountInfoInteger(ACCOUNT_LOGIN), DBEsc(cfg))))
        g_sessionId = (int)DBLastInsertId();
    else
        PrintFormat("AurumBlock DB: session insert failed — error %d", GetLastError());
}

void DBLogPnLSnapshot(const string trigger);   // forward declaration

void DBClose()
{
    if(g_db == INVALID_HANDLE) return;
    if(InpLogSnapshots && g_sessionId > 0 && !IsTesting())
        DBLogPnLSnapshot("deinit");
    if(g_sessionId > 0)
        DatabaseExecute(g_db, StringFormat(
            "UPDATE sessions SET stop_time=%d WHERE id=%d;", (long)TimeCurrent(), g_sessionId));
    DatabaseClose(g_db);
    g_db = INVALID_HANDLE;
}

void DBArchiveAndPrune()
{
    if(g_db == INVALID_HANDLE || IsTesting()) return;
    MqlDateTime dt; TimeToStruct(LocalNow(), dt);
    if(dt.mon == g_lastArchiveMonth) return;
    int prevMonth = g_lastArchiveMonth;
    g_lastArchiveMonth = dt.mon;
    if(prevMonth < 0) return;   // first run — record current month, skip archive
    int archYear = dt.year, archMon = dt.mon - 1;
    if(archMon <= 0) { archMon = 12; archYear--; }
    string archName = StringFormat("AurumBlock_%04d_%02d.db", archYear, archMon);
    string archFull = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + archName;
    DatabaseTransactionBegin(g_db);
    if(DatabaseExecute(g_db, StringFormat("ATTACH DATABASE '%s' AS arch;", DBEsc(archFull))))
    {
        DatabaseExecute(g_db, "CREATE TABLE IF NOT EXISTS arch.sessions AS SELECT * FROM sessions WHERE 0;");
        DatabaseExecute(g_db, "CREATE TABLE IF NOT EXISTS arch.blocks AS SELECT * FROM blocks WHERE 0;");
        DatabaseExecute(g_db, "CREATE TABLE IF NOT EXISTS arch.zone_touches AS SELECT * FROM zone_touches WHERE 0;");
        DatabaseExecute(g_db, "CREATE TABLE IF NOT EXISTS arch.filter_events AS SELECT * FROM filter_events WHERE 0;");
        DatabaseExecute(g_db, "CREATE TABLE IF NOT EXISTS arch.trades AS SELECT * FROM trades WHERE 0;");
        DatabaseExecute(g_db, "CREATE TABLE IF NOT EXISTS arch.cycles AS SELECT * FROM cycles WHERE 0;");
        DatabaseExecute(g_db, "CREATE TABLE IF NOT EXISTS arch.pnl_snapshots AS SELECT * FROM pnl_snapshots WHERE 0;");
        DatabaseExecute(g_db, "INSERT OR IGNORE INTO arch.sessions        SELECT * FROM sessions;");
        DatabaseExecute(g_db, "INSERT OR IGNORE INTO arch.blocks          SELECT * FROM blocks;");
        DatabaseExecute(g_db, "INSERT OR IGNORE INTO arch.zone_touches    SELECT * FROM zone_touches;");
        DatabaseExecute(g_db, "INSERT OR IGNORE INTO arch.filter_events   SELECT * FROM filter_events;");
        DatabaseExecute(g_db, "INSERT OR IGNORE INTO arch.trades          SELECT * FROM trades;");
        DatabaseExecute(g_db, "INSERT OR IGNORE INTO arch.cycles          SELECT * FROM cycles;");
        DatabaseExecute(g_db, "INSERT OR IGNORE INTO arch.pnl_snapshots   SELECT * FROM pnl_snapshots;");
        DatabaseExecute(g_db, "DETACH DATABASE arch;");
    }
    DatabaseTransactionCommit(g_db);
    long cutoff = (long)TimeCurrent() - 30LL * 86400;
    DatabaseTransactionBegin(g_db);
    DatabaseExecute(g_db, StringFormat("DELETE FROM sessions      WHERE start_time    < %d;", cutoff));
    DatabaseExecute(g_db, StringFormat("DELETE FROM blocks        WHERE created_at    < %d;", cutoff));
    DatabaseExecute(g_db, StringFormat("DELETE FROM zone_touches  WHERE touched_at    < %d;", cutoff));
    DatabaseExecute(g_db, StringFormat("DELETE FROM filter_events WHERE event_time    < %d;", cutoff));
    DatabaseExecute(g_db, StringFormat("DELETE FROM trades        WHERE placed_at     < %d;", cutoff));
    DatabaseExecute(g_db, StringFormat("DELETE FROM cycles        WHERE open_time     < %d;", cutoff));
    DatabaseExecute(g_db, StringFormat("DELETE FROM pnl_snapshots WHERE snapshot_time < %d;", cutoff));
    DatabaseTransactionCommit(g_db);
    DatabaseExecute(g_db, "VACUUM;");
    PrintFormat("AurumBlock DB: archived to %s, pruned records older than 30 days.", archName);
}

void DBLogBlock(bool isBull, double high, double low,
                double topH, double topL, double botH, double botL, datetime createdAt)
{
    if(!InpLogBlocks || g_db == INVALID_HANDLE || IsTesting()) return;
    if(g_currentBlockId > 0)
        DatabaseExecute(g_db, StringFormat(
            "UPDATE blocks SET invalidated_at=%d,invalidated_reason='replaced'"
            " WHERE id=%d AND invalidated_at IS NULL;",
            (long)createdAt, g_currentBlockId));
    if(DatabaseExecute(g_db, StringFormat(
        "INSERT INTO blocks(session_id,created_at,is_bull,block_high,block_low,size_pips,"
        "top_zone_high,top_zone_low,bot_zone_high,bot_zone_low) "
        "VALUES(%d,%d,%d,%.5f,%.5f,%.2f,%.5f,%.5f,%.5f,%.5f);",
        g_sessionId, (long)createdAt, isBull ? 1 : 0,
        high, low, (high - low) / PIP_VALUE, topH, topL, botH, botL)))
        g_currentBlockId = (int)DBLastInsertId();
}

void DBLogZoneTouch(const string zone, double price, int count)
{
    if(!InpLogBlocks || g_db == INVALID_HANDLE || IsTesting()) return;
    int exhausted = (count >= TOUCH_WARN_COUNT) ? 1 : 0;
    DatabaseExecute(g_db, StringFormat(
        "INSERT INTO zone_touches(block_id,session_id,touched_at,zone,touch_count,price,exhausted) "
        "VALUES(%d,%d,%d,'%s',%d,%.5f,%d);",
        g_currentBlockId, g_sessionId, (long)TimeCurrent(), zone, count, price, exhausted));
    if(exhausted && g_currentBlockId > 0 &&
       g_botTouchCount >= TOUCH_WARN_COUNT && g_botUnstable &&
       g_topTouchCount >= TOUCH_WARN_COUNT && g_topUnstable)
        DatabaseExecute(g_db, StringFormat(
            "UPDATE blocks SET invalidated_at=%d,invalidated_reason='exhausted'"
            " WHERE id=%d AND invalidated_at IS NULL;",
            (long)TimeCurrent(), g_currentBlockId));
}

void DBLogFilterEvent(const string filterType, const string state, const string detail)
{
    if(!InpLogFilters || g_db == INVALID_HANDLE || IsTesting()) return;
    long now = (long)TimeCurrent();
    int idx = (filterType=="news") ? 0 : (filterType=="session_pause") ? 1 :
              (filterType=="trading_window") ? 2 : (filterType=="force_close") ? 3 : 4;
    long duration = (state == "off" && g_filterOnTimes[idx] > 0)
                    ? now - (long)g_filterOnTimes[idx] : 0;
    if(state == "on") g_filterOnTimes[idx] = (datetime)now;
    DatabaseExecute(g_db, StringFormat(
        "INSERT INTO filter_events(session_id,event_time,filter_type,state,detail,duration_sec) "
        "VALUES(%d,%d,'%s','%s','%s',%d);",
        g_sessionId, now, filterType, state, DBEsc(detail), duration));
}

void DBCheckFilterTransitions()
{
    if(!InpLogFilters || g_db == INVALID_HANDLE || IsTesting()) return;
    bool newsNow    = IsNewsTime();
    bool pauseNow   = IsSessionPauseTime();
    bool tradingNow = IsTradingAllowed();
    bool forceNow   = IsForceCloseTime();
    bool webNow     = IsPaused();
    if(newsNow    != g_prevNews)
        { DBLogFilterEvent("news",           newsNow  ? "on":"off", newsNow  ? DBGetActiveNewsName() : ""); g_prevNews = newsNow; }
    if(pauseNow   != g_prevSessionPause)
        { DBLogFilterEvent("session_pause",  pauseNow ? "on":"off", pauseNow ? DBGetActivePauseName(): ""); g_prevSessionPause = pauseNow; }
    if(tradingNow != g_prevTradingAllowed)
        { DBLogFilterEvent("trading_window", tradingNow ? "off":"on", ""); g_prevTradingAllowed = tradingNow; }
    if(forceNow   != g_prevForceClose)
        { DBLogFilterEvent("force_close",    forceNow ? "on":"off", ""); g_prevForceClose = forceNow; }
    if(webNow     != g_prevWebPause)
        { DBLogFilterEvent("web_pause",      webNow   ? "on":"off", ""); g_prevWebPause = webNow; }
}

void DBLogTrade(const string tradeType, ulong ticket, double lots, double price, double tp)
{
    if(!InpLogTrades || g_db == INVALID_HANDLE || IsTesting() || ticket == 0) return;
    DatabaseExecute(g_db, StringFormat(
        "INSERT INTO trades(session_id,block_id,ticket,type,lots,entry_price,tp,placed_at) "
        "VALUES(%d,%d,%d,'%s',%.2f,%.5f,%.5f,%d);",
        g_sessionId, g_currentBlockId, (long)ticket, tradeType, lots, price, tp, (long)TimeCurrent()));
}

void DBLogTradeClose(ulong ticket, double closePrice, double profit, double commission, double swap, const string reason)
{
    if(!InpLogTrades || g_db == INVALID_HANDLE || IsTesting() || ticket == 0) return;
    long now = (long)TimeCurrent();
    long filledAt = 0;
    if(HistorySelect(now - 7 * 86400, now + 1))
    {
        int tot = HistoryDealsTotal();
        for(int i = 0; i < tot; i++)
        {
            ulong deal = HistoryDealGetTicket(i);
            if((ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) != ticket) continue;
            if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
            filledAt = (long)HistoryDealGetInteger(deal, DEAL_TIME);
            break;
        }
    }
    string filledStr = (filledAt > 0) ? StringFormat("%d", filledAt) : "NULL";
    DatabaseExecute(g_db, StringFormat(
        "UPDATE trades SET filled_at=%s,closed_at=%d,close_price=%.5f,"
        "profit=%.2f,commission=%.2f,swap=%.2f,close_reason='%s' "
        "WHERE ticket=%d AND session_id=%d;",
        filledStr, now, closePrice, profit, commission, swap, reason,
        (long)ticket, g_sessionId));
}

void DBUpdateOpenTickets()
{
    if(!InpLogTrades || g_db == INVALID_HANDLE || IsTesting()) return;
    g_openTicketCount = 0;
    int total = PositionsTotal();
    if(ArraySize(g_openTickets) < total + 1) ArrayResize(g_openTickets, total + 4);
    for(int i = total - 1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(PositionGetString(POSITION_SYMBOL)  != Symbol())     continue;
        if(PositionGetInteger(POSITION_MAGIC)  != MAGIC_NUMBER) continue;
        g_openTickets[g_openTicketCount++] = t;
    }
}

void DBDetectClosedTrades()
{
    if(!InpLogTrades || g_db == INVALID_HANDLE || IsTesting() || g_openTicketCount == 0) return;
    datetime now = TimeCurrent();
    bool needHistory = false;
    for(int i = 0; i < g_openTicketCount && !needHistory; i++)
    {
        ulong ticket = g_openTickets[i];
        bool stillOpen = false;
        for(int j = PositionsTotal() - 1; j >= 0; j--)
            if(PositionGetTicket(j) == ticket) { stillOpen = true; break; }
        if(!stillOpen) needHistory = true;
    }
    if(!needHistory) return;
    HistorySelect(now - 7 * 86400, now + 1);
    for(int i = 0; i < g_openTicketCount; i++)
    {
        ulong ticket = g_openTickets[i];
        bool stillOpen = false;
        for(int j = PositionsTotal() - 1; j >= 0; j--)
            if(PositionGetTicket(j) == ticket) { stillOpen = true; break; }
        if(stillOpen) continue;
        int tot = HistoryDealsTotal();
        for(int k = 0; k < tot; k++)
        {
            ulong deal = HistoryDealGetTicket(k);
            if(HistoryDealGetString(deal, DEAL_SYMBOL)  != Symbol())     continue;
            if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != MAGIC_NUMBER) continue;
            if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
            if((ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) != ticket) continue;
            double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
            double comm   = HistoryDealGetDouble(deal, DEAL_COMMISSION);
            double swap   = HistoryDealGetDouble(deal, DEAL_SWAP);
            double price  = HistoryDealGetDouble(deal, DEAL_PRICE);
            ENUM_DEAL_REASON dr = (ENUM_DEAL_REASON)HistoryDealGetInteger(deal, DEAL_REASON);
            string reason = (dr == DEAL_REASON_TP) ? "tp"
                          : (dr == DEAL_REASON_CLIENT || dr == DEAL_REASON_MOBILE || dr == DEAL_REASON_WEB)
                            ? "manual" : "force_close";
            DBLogTradeClose(ticket, price, profit, comm, swap, reason);
            break;
        }
    }
}

void DBLogCycle(EState fromState, datetime cycleStart)
{
    if(!InpLogTrades || g_db == INVALID_HANDLE || IsTesting()) return;
    if(fromState != STATE_SELLS && fromState != STATE_BUYS) return;
    string direction = (fromState == STATE_SELLS) ? "sell" : "buy";
    if(!HistorySelect(0, TimeCurrent() + 1)) return;
    int    total    = HistoryDealsTotal();
    double netPnl   = 0, peakLots = 0, lotSum = 0;
    int    scaleIns = 0;
    datetime firstIn = 0, lastOut = 0;
    for(int i = g_cycleStartDealCount; i < total; i++)
    {
        ulong deal = HistoryDealGetTicket(i);
        if(HistoryDealGetString(deal, DEAL_SYMBOL)  != Symbol())     continue;
        if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != MAGIC_NUMBER) continue;
        ENUM_DEAL_ENTRY de = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
        if(de == DEAL_ENTRY_IN)
        {
            double lots = HistoryDealGetDouble(deal, DEAL_VOLUME);
            lotSum += lots;
            if(lotSum > peakLots) peakLots = lotSum;
            string cmt = HistoryDealGetString(deal, DEAL_COMMENT);
            if(StringFind(cmt, "AUR_SS") >= 0 || StringFind(cmt, "AUR_BS") >= 0) scaleIns++;
            datetime t = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
            if(firstIn == 0) firstIn = t;
        }
        else if(de == DEAL_ENTRY_OUT)
        {
            netPnl += HistoryDealGetDouble(deal, DEAL_PROFIT)
                    + HistoryDealGetDouble(deal, DEAL_COMMISSION)
                    + HistoryDealGetDouble(deal, DEAL_SWAP);
            lotSum -= HistoryDealGetDouble(deal, DEAL_VOLUME);
            lastOut = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
        }
    }
    if(firstIn == 0 || lastOut == 0) return;
    DatabaseExecute(g_db, StringFormat(
        "INSERT INTO cycles(session_id,block_id,direction,open_time,close_time,duration_sec,"
        "scale_in_count,peak_lots,net_pnl,above_be,max_dd) "
        "VALUES(%d,%d,'%s',%d,%d,%d,%d,%.2f,%.2f,%d,%.2f);",
        g_sessionId, g_currentBlockId, direction,
        (long)firstIn, (long)lastOut, (long)lastOut - (long)firstIn,
        scaleIns, peakLots, netPnl, netPnl > 0.10 ? 1 : 0, g_cyclePeakDD));
}

void DBLogPnLSnapshot(const string trigger)
{
    if(!InpLogSnapshots || g_db == INVALID_HANDLE || IsTesting()) return;
    datetime dayStart  = LocalDayStart();
    datetime weekStart = LocalWeekStart();
    int ciclosToday = 0, ciclosWeek = 0;
    if(HistorySelect(weekStart, TimeCurrent() + 1))
    {
        int tot = HistoryDealsTotal();
        for(int i = 0; i < tot; i++)
        {
            ulong deal = HistoryDealGetTicket(i);
            if(HistoryDealGetString(deal, DEAL_SYMBOL) != Symbol()) continue;
            if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != MAGIC_NUMBER) continue;
            if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
            string cmt = HistoryDealGetString(deal, DEAL_COMMENT);
            if(StringFind(cmt, "AUR_SS") >= 0 || StringFind(cmt, "AUR_BS") >= 0) continue;
            datetime t = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
            if(t >= dayStart) ciclosToday++;
            ciclosWeek++;
        }
    }
    int openPos = CountPositions(POSITION_TYPE_SELL) + CountPositions(POSITION_TYPE_BUY);
    DatabaseExecute(g_db, StringFormat(
        "INSERT INTO pnl_snapshots(session_id,snapshot_time,trigger,daily_realized,floating_pnl,"
        "open_positions,cycles_today,cycles_week,be_cycles,above_be_cycles) "
        "VALUES(%d,%d,'%s',%.2f,%.2f,%d,%d,%d,0,0);",
        g_sessionId, (long)TimeCurrent(), trigger,
        GetDailyProfit(), GetFloatingPnL(), openPos, ciclosToday, ciclosWeek));
}

//+------------------------------------------------------------------+
//|  ManageTrade                                                     |
//+------------------------------------------------------------------+
void ManageTrade()
{
    if(!g_initialized || g_activeIdx < 0) return;
    if(IsPaused()) return;
    DBCheckFilterTransitions();
    DBDetectClosedTrades();
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
    // END OF DAY — 19:45 onwards: close if positive, allow scale-ins if negative
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
        if(InpLogSnapshots && g_db != INVALID_HANDLE && !IsTesting())
        {
            MqlDateTime _d; TimeToStruct(LocalNow(), _d);
            datetime _today = (datetime)(_d.year * 10000 + _d.mon * 100 + _d.day);
            if(_today != g_lastSnapshotDate) { g_lastSnapshotDate = _today; DBLogPnLSnapshot("end_of_day"); }
        }
    }
    // SIZE GUARD
    double abH = g_blocks[g_activeIdx].blockHigh;
    double abL = g_blocks[g_activeIdx].blockLow;
    // Include the live (unclosed) bar's range so TP tracks the same midline as the visual drawing.
    if(g_blocks[g_activeIdx].startTime < iTime(Symbol(), Period(), 0))
    {
        abH = MathMax(abH, iHigh(Symbol(), Period(), 0));
        abL = MathMin(abL, iLow(Symbol(), Period(), 0));
    }
    if(((abH-abL)/PIP_VALUE) < BLK_MIN_SIZE) return;
    double zs      = (abH-abL)*(ZONE_PCT/100.0);
    double topBand = abH-zs, botBand = abL+zs;
    double midPrice= (abH+abL)/2.0;
    double midTop  = midPrice+zs;
    double midBot  = midPrice-zs;
    double dist    = InpMinOrderDist * PIP_VALUE;
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

    // DB: detect cycle open/close transitions
    if(g_prevState != STATE_SELLS && g_prevState != STATE_BUYS &&
       (g_state == STATE_SELLS || g_state == STATE_BUYS))
    {
        g_cycleOpenTime   = TimeCurrent();
        g_tradeBlockTime  = g_blocks[g_activeIdx].startTime;
        for(int _i = PositionsTotal()-1; _i >= 0; _i--)
        {
            ulong _t = PositionGetTicket(_i);
            if(!PositionSelectByTicket(_t)) continue;
            if(PositionGetString(POSITION_SYMBOL)  != Symbol())     continue;
            if(PositionGetInteger(POSITION_MAGIC)  != MAGIC_NUMBER) continue;
            datetime _pt = (datetime)PositionGetInteger(POSITION_TIME);
            if(_pt < g_cycleOpenTime) g_cycleOpenTime = _pt;
        }
        // Snapshot deal count so DBLogCycle scans only this cycle's deals,
        // even when the previous cycle closed in the same second.
        HistorySelect(0, TimeCurrent() + 1);
        g_cycleStartDealCount = HistoryDealsTotal();
        g_cyclePeakDD = 0.0;
    }
    if((g_prevState == STATE_SELLS || g_prevState == STATE_BUYS) && g_state == STATE_IDLE)
    {
        DBLogCycle(g_prevState, g_cycleOpenTime);
        DBLogPnLSnapshot("cycle_close");
        g_cycleOpenTime  = 0;
        g_tradeBlockTime = 0;
        g_cyclePeakDD    = 0.0;
    }
    g_prevState = g_state;

    // Track worst floating drawdown each tick while a cycle is active
    if(g_state == STATE_SELLS || g_state == STATE_BUYS)
    {
        double _fp = 0.0;
        for(int _fi = PositionsTotal()-1; _fi >= 0; _fi--)
        {
            ulong _ft = PositionGetTicket(_fi);
            if(!PositionSelectByTicket(_ft)) continue;
            if(PositionGetString(POSITION_SYMBOL)  != Symbol())     continue;
            if(PositionGetInteger(POSITION_MAGIC)  != MAGIC_NUMBER) continue;
            _fp += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        }
        if(_fp < g_cyclePeakDD) g_cyclePeakDD = _fp;
    }

    bool canOpen = IsTradingAllowed() && !IsNewsTime() && !IsSessionPauseTime() && !g_noNewCycles;

    // A band is "exhausted" once it has been touched ≥ TOUCH_WARN_COUNT times.
    // No new initial entries are opened on an exhausted side; the opposite side
    // (if still valid) continues to operate normally.
    bool topValid = !g_topUnstable || g_topTouchCount < TOUCH_WARN_COUNT;
    bool botValid = !g_botUnstable || g_botTouchCount < TOUCH_WARN_COUNT;

    if(g_state == STATE_IDLE)
    {
        if(canOpen)
        {
            if(topValid && sellPend == 0 && CountPositions(POSITION_TYPE_SELL) == 0)
            {
                double _lT = GetLots();
                bool   _sl = (topBand > ask) && g_trade.SellLimit(_lT, topBand, Symbol(), 0, midTop, ORDER_TIME_GTC, 0, "AUR_SL");
                if(!_sl) g_trade.Sell(_lT, NULL, 0.0, 0.0, midTop, "AUR_SM");
                ulong _tk = g_trade.ResultOrder();
                if(_tk > 0) DBLogTrade(_sl ? "sell_limit" : "sell_market", _tk, _lT, _sl ? topBand : g_trade.ResultPrice(), midTop);
            }
            if(botValid && buyPend == 0 && CountPositions(POSITION_TYPE_BUY) == 0)
            {
                double _lB = GetLots();
                bool   _bl = (botBand < bid) && g_trade.BuyLimit(_lB, botBand, Symbol(), 0, midBot, ORDER_TIME_GTC, 0, "AUR_BL");
                if(!_bl) g_trade.Buy(_lB, NULL, 0.0, 0.0, midBot, "AUR_BM");
                ulong _tk = g_trade.ResultOrder();
                if(_tk > 0) DBLogTrade(_bl ? "buy_limit" : "buy_market", _tk, _lB, _bl ? botBand : g_trade.ResultPrice(), midBot);
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
        if(!g_tpFrozen && g_blocks[g_activeIdx].startTime == g_tradeBlockTime)
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
                    double newLots  = NormalizeDouble(lastLots * InpLotMultiplier, 2);
                    double totalVol = GetTotalVolume(POSITION_TYPE_SELL);
                    double curBE    = GetWeightedBreakEven(POSITION_TYPE_SELL);
                    double newBE    = NormalizeDouble((curBE*totalVol + bid*newLots)/(totalVol+newLots), digits);
                    double newBECost = NormalizeDouble(newBE - COST_PER_LOT, digits);
                    if(g_trade.Sell(newLots, NULL, 0.0, 0.0, newBECost, "AUR_SS"))
                    {
                        UpdateAllTPs(POSITION_TYPE_SELL, newBECost);
                        g_tpFrozen = false;
                        DBLogTrade("scale_sell", g_trade.ResultOrder(), newLots, g_trade.ResultPrice(), newBECost);
                    }
                }
            }
        }
    }
    else if(g_state == STATE_BUYS)
    {
        if(!g_tpFrozen && g_blocks[g_activeIdx].startTime == g_tradeBlockTime)
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
                    double newLots  = NormalizeDouble(lastLots * InpLotMultiplier, 2);
                    double totalVol = GetTotalVolume(POSITION_TYPE_BUY);
                    double curBE    = GetWeightedBreakEven(POSITION_TYPE_BUY);
                    double newBE    = NormalizeDouble((curBE*totalVol + ask*newLots)/(totalVol+newLots), digits);
                    double newBECost = NormalizeDouble(newBE + COST_PER_LOT, digits);
                    if(g_trade.Buy(newLots, NULL, 0.0, 0.0, newBECost, "AUR_BS"))
                    {
                        UpdateAllTPs(POSITION_TYPE_BUY, newBECost);
                        g_tpFrozen = false;
                        DBLogTrade("scale_buy", g_trade.ResultOrder(), newLots, g_trade.ResultPrice(), newBECost);
                    }
                }
            }
        }
    }
    DBUpdateOpenTickets();
}

//+------------------------------------------------------------------+
//|  Dashboard helpers                                               |
//+------------------------------------------------------------------+

// Format seconds as "12m30s" (< 1 h) or "1h05m" (≥ 1 h).
string FormatTimer(long secs)
{
    if(secs <= 0) return "0s";
    if(secs < 3600)
        return StringFormat("%dm%02ds", (int)(secs / 60), (int)(secs % 60));
    return StringFormat("%dh%02dm", (int)(secs / 3600), (int)((secs % 3600) / 60));
}

// Returns seconds until trading resumes from an active news block.
// Fills outName with the event name. Returns -1 when not in a news block.
long GetNewsBlockInfo(string &outName)
{
    datetime now = TimeCurrent() - (datetime)(SERVER_OFFSET * 3600);   // UTC
    for(int i = 0; i < g_newsCount; i++)
    {
        long diff = (long)now - (long)g_newsEvents[i];
        if(diff >= -(long)NEWS_PRE_SEC && diff <= (long)NEWS_POST_SEC)
        {
            outName = g_newsNames[i];
            datetime resume = g_newsEvents[i] + (datetime)NEWS_POST_SEC;
            long rem = (long)resume - (long)now;
            return (rem > 0) ? rem : 0;
        }
    }
    return -1;
}

// Returns seconds until trading resumes from an active session pause.
// Fills outSession with the session name. Returns -1 when not in a session pause.
long GetSessionPauseInfo(string &outSession)
{
    MqlDateTime dt;
    TimeToStruct(LocalNow(), dt);
    int curMin = dt.hour * 60 + dt.min;
    int w = PAUSE_WINDOW_MIN;

    int    openMin[4];
    string names[4];
    openMin[0] = TOKYO_H   * 60 + TOKYO_M;    names[0] = "Tokyo";
    openMin[1] = LONDON_H  * 60 + LONDON_M;   names[1] = "London";
    openMin[2] = NYFOREX_H * 60 + NYFOREX_M;  names[2] = "NY Forex";
    openMin[3] = NYSE_H    * 60 + NYSE_M;      names[3] = "NYSE";

    for(int i = 0; i < 4; i++)
    {
        if(!IsNearOpen(curMin, openMin[i], w)) continue;
        outSession = names[i];
        int endMin = openMin[i] + w;
        // Remaining minutes to the end of the pause window.
        int remMin = endMin - curMin;
        if(remMin >  720) remMin -= 1440;
        if(remMin < -720) remMin += 1440;
        long remSec = (long)remMin * 60 - (long)dt.sec;
        return (remSec > 0) ? remSec : 0;
    }
    return -1;
}

//+------------------------------------------------------------------+
//  PREVIEW: seconds until the next session pause begins.            |
//  Only active when not already inside a pause window.              |
//  outSession: name of the upcoming session                         |
//  Returns seconds until pause start, or -1 if outside window.     |
//+------------------------------------------------------------------+
long GetNextSessionPauseStart(string &outSession)
{
    if(IsSessionPauseTime()) return -1;   // already in a pause — status row handles it

    MqlDateTime dt;
    TimeToStruct(LocalNow(), dt);
    int curMin = dt.hour * 60 + dt.min;
    int curSec = dt.sec;

    int    openMin[4];
    string names[4];
    openMin[0] = TOKYO_H   * 60 + TOKYO_M;    names[0] = "Tokyo";
    openMin[1] = LONDON_H  * 60 + LONDON_M;   names[1] = "London";
    openMin[2] = NYFOREX_H * 60 + NYFOREX_M;  names[2] = "NY Forex";
    openMin[3] = NYSE_H    * 60 + NYSE_M;      names[3] = "NYSE";

    long bestSecs = -1;

    for(int i = 0; i < 4; i++)
    {
        // Pause starts PAUSE_WINDOW_MIN minutes before session open.
        int pauseStart = openMin[i] - PAUSE_WINDOW_MIN;
        if(pauseStart < 0) pauseStart += 1440;

        // Forward circular distance (in minutes) from curMin to pauseStart.
        int fwdMin = (pauseStart - curMin + 1440) % 1440;
        if(fwdMin == 0 || fwdMin > NEXT_SESSION_WARN_MIN) continue;

        long secs = (long)fwdMin * 60 - (long)curSec;
        if(secs < 0) secs = 0;

        if(bestSecs < 0 || secs < bestSecs)
        {
            bestSecs = secs;
            outSession = names[i];
        }
    }
    return bestSecs;
}

//+------------------------------------------------------------------+
//  PREVIEW: information about the next relevant news event.         |
//  outSecsToBlock: seconds until the pre-block starts (bot pauses)  |
//  outSecsToEvent: seconds until the event itself                   |
//  outName: event name                                               |
//  outLocalTime: local time "HH:MM" (UTC+1)                         |
//  Returns true if an event falls within NEXT_NEWS_SHOW_H hours.    |
//+------------------------------------------------------------------+
bool GetNextNewsInfo(long &outSecsToBlock, long &outSecsToEvent,
                     string &outName, string &outLocalTime)
{
    if(IsNewsTime()) return false;   // already in a news block — status row handles it

    datetime now = TimeCurrent() - (datetime)(SERVER_OFFSET * 3600);   // UTC
    long showWindow = (long)NEXT_NEWS_SHOW_H * 3600;

    for(int i = 0; i < g_newsCount; i++)
    {
        long secsToEvent = (long)g_newsEvents[i] - (long)now;
        if(secsToEvent <= 0)          continue;   // past event
        if(secsToEvent > showWindow)  break;       // array is sorted; farther events → stop

        long secsToBlock = secsToEvent - (long)NEWS_PRE_SEC;
        if(secsToBlock < 0) continue;   // pre-block already started (IsNewsTime should be true)

        outSecsToBlock = secsToBlock;
        outSecsToEvent = secsToEvent;
        outName        = g_newsNames[i];

        // Format event time in local UTC+1
        datetime localEvt = g_newsEvents[i] + (datetime)(LOCAL_OFFSET * 3600);
        MqlDateTime evtDt;
        TimeToStruct(localEvt, evtDt);
        outLocalTime = StringFormat("%02d:%02d", evtDt.hour, evtDt.min);
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
// Calculates the default panel position (pinned to bottom-left).
// Called every UpdateDashboard() tick when the user has NOT dragged
// the panel; once dragged, g_panDragged=true and the stored position
// is used unchanged (so the panel stays wherever the user left it).
void EnsurePanelPos()
{
    if(!g_panDragged)
    {
        long chartH = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
        g_panX = 10 * InpUIScale;
        g_panY = (int)MathMax(0, chartH - (DASH_PAN_BOT + DASH_PAN_H) * InpUIScale);
    }
}

//+------------------------------------------------------------------+
//|  Dashboard — background bitmap (call once from OnInit)           |
//+------------------------------------------------------------------+
// Builds an ARGB pixel buffer and registers it as an in-memory resource.
// OBJ_BITMAP_LABEL renders this buffer with true per-pixel alpha, giving
// a genuine semi-transparent overlay over the chart candles.
// C'14,18,32' (dark navy) in ARGB pixel order = (A<<24)|(R<<16)|(G<<8)|B.
void CreateDashboardBitmap()
{
    // Physical pixel dimensions — on HiDPI/Retina (InpUIScale=2) the bitmap is
    // built at 2× physical resolution so it renders at the correct logical size.
    int pw = DASH_PAN_W * InpUIScale;
    int ph = DASH_PAN_H * InpUIScale;

    uint pixels[];
    ArrayResize(pixels, pw * ph);

    // ── Body fill ─────────────────────────────────────────────────
    uint fillPx = ((uint)DASH_PAN_ALPHA << 24) | (14u << 16) | (18u << 8) | 32u;
    ArrayFill(pixels, 0, pw * ph, fillPx);

    // ── 1-pixel cobalt border (fully opaque) ─────────────────────
    uint brdPx = (255u << 24) | (55u << 16) | (80u << 8) | 160u;
    for(int x = 0; x < pw; x++)
    {
        pixels[x]                        = brdPx;  // top edge
        pixels[(ph - 1) * pw + x]        = brdPx;  // bottom edge
    }
    for(int y = 0; y < ph; y++)
    {
        pixels[y * pw]                   = brdPx;  // left edge
        pixels[y * pw + pw - 1]          = brdPx;  // right edge
    }

    ResourceCreate(DASH_PAN_RES,
                   pixels, pw, ph,
                   0, 0, pw,
                   COLOR_FORMAT_ARGB_RAW);
}

//+------------------------------------------------------------------+
//|  Dashboard                                                       |
//+------------------------------------------------------------------+
void DashLabel(const string name, int yoff, const string text, color clr)
{
    // yoff: row baseline measured from panel BOTTOM (logical px, same scale as before).
    // Converts to absolute chart coords: absY = panelTop + (panH - yoff_from_panBot).
    // CORNER_LEFT_UPPER + ANCHOR_LEFT_LOWER keeps the same baseline position regardless
    // of where the panel was dragged to.
    int absX = g_panX + 20 * InpUIScale;
    int absY = g_panY + (DASH_PAN_BOT + DASH_PAN_H - yoff) * InpUIScale;
    if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_LEFT_LOWER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  absX);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  absY);
    ObjectSetString (0, name, OBJPROP_FONT,       "Consolas");
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   9);
    ObjectSetString (0, name, OBJPROP_TEXT,       text);
    ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

void UpdateDashboard()
{
    // ── State detection ──────────────────────────────────────────
    string newsName = "", sessName = "";
    long   newsSecs  = GetNewsBlockInfo(newsName);
    long   sessSecs  = GetSessionPauseInfo(sessName);
    bool   paused    = IsPaused();

    string statText;
    color  statColor;
    if(paused)
    {
        statText  = "\x25A0  PAUSED  (web panel)";   // filled square
        statColor = C'248,113,113';                   // red
    }
    else if(newsSecs >= 0)
    {
        // Truncate name to ≤18 chars so it fits the panel width
        string shortName = (StringLen(newsName) > 18) ? StringSubstr(newsName, 0, 18) + ".." : newsName;
        statText  = "\x25B6  NEWS  " + shortName + "   \xBB " + FormatTimer(newsSecs);
        statColor = C'251,191,36';                    // amber
    }
    else if(sessSecs >= 0)
    {
        statText  = "\x23F8  " + sessName + " pause   \xBB " + FormatTimer(sessSecs);
        statColor = C'251,191,36';                    // amber
    }
    else
    {
        statText  = "\x25CF  ACTIVE";
        statColor = C'74,222,128';                    // green
    }

    // ── Box info line ─────────────────────────────────────────────
    string boxText;
    if(g_activeIdx >= 0)
    {
        double bH = g_blocks[g_activeIdx].blockHigh;
        double bL = g_blocks[g_activeIdx].blockLow;
        double pips = (bH - bL) / PIP_VALUE;
        // Touch counters: "↑2t" = top band touched 2×, "!↓3t" = bottom exhausted
        // Avoid mixing %s/%d in StringFormat (MQL5 quirk) — use concatenation instead.
        string topTag = (g_topTouchCount >= TOUCH_WARN_COUNT ? "!" : "")
                        + "\x2191" + IntegerToString(g_topTouchCount) + "t";
        string botTag = (g_botTouchCount >= TOUCH_WARN_COUNT ? "!" : "")
                        + "\x2193" + IntegerToString(g_botTouchCount) + "t";
        boxText = StringFormat("Box  %.2f \x2013 %.2f  [ %.1f p ]  ", bH, bL, pips)
                  + topTag + "  " + botTag;
    }
    else
        boxText = "Box  \x2013 \x2013";

    // ── Trade statistics ─────────────────────────────────────────
    datetime weekStart = LocalWeekStart();
    datetime dayStart  = LocalDayStart();

    int  ciclosToday = 0, ciclosWeek = 0;
    int  beCyclesToday = 0, aboveCyclesToday = 0;
    int  beCyclesWeek  = 0, aboveCyclesWeek  = 0;
    long minSec = -1, maxSec = 0, sumSec = 0;
    int  durN = 0;

    if(HistorySelect(weekStart, TimeCurrent() + 1))
    {
        int total = HistoryDealsTotal();

        long     posId[];
        datetime posOpen[];
        datetime posClose[];
        int pc = 0;

        datetime exitTime[];
        double   exitNet[];
        int      exitDir[];
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

        // Cycle grouping: same direction within 30 seconds.
        // lastT is the time of the last exit in the group — used to split today vs week.
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
                    bool tod = (lastT >= dayStart);
                    if(curNet > 0.10) { aboveCyclesWeek++; if(tod) aboveCyclesToday++; }
                    else              { beCyclesWeek++;    if(tod) beCyclesToday++;    }
                    curNet = exitNet[i]; lastT = exitTime[i]; lastD = exitDir[i];
                }
            }
            bool tod = (lastT >= dayStart);
            if(curNet > 0.10) { aboveCyclesWeek++; if(tod) aboveCyclesToday++; }
            else              { beCyclesWeek++;    if(tod) beCyclesToday++;    }
        }

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
    string sMin = (minSec < 0) ? "--" : (minSec < 3600)
        ? StringFormat("%dm", (int)(minSec/60))
        : StringFormat("%dh%02dm", (int)(minSec/3600), (int)(minSec%3600)/60);

    long avgSec = (durN > 0) ? (sumSec / durN) : 0;
    string sAvg = (avgSec < 3600)
        ? StringFormat("%dm", (int)(avgSec/60))
        : StringFormat("%dh%02dm", (int)(avgSec/3600), (int)(avgSec%3600)/60);

    string sMax = (maxSec < 3600)
        ? StringFormat("%dm", (int)(maxSec/60))
        : StringFormat("%dh%02dm", (int)(maxSec/3600), (int)(maxSec%3600)/60);

    // ── Background panel (OBJ_BITMAP_LABEL — true ARGB transparency) ──
    // EnsurePanelPos() pins the panel to the chart bottom when !g_panDragged,
    // or keeps the user-dragged position when g_panDragged=true.
    EnsurePanelPos();
    if(ObjectFind(0, N_DASHBG) < 0)
    {
        ObjectCreate(0, N_DASHBG, OBJ_BITMAP_LABEL, 0, 0, 0);
        ObjectSetString (0, N_DASHBG, OBJPROP_BMPFILE,    DASH_PAN_RES);
        ObjectSetInteger(0, N_DASHBG, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
        ObjectSetInteger(0, N_DASHBG, OBJPROP_BACK,       false);
        ObjectSetInteger(0, N_DASHBG, OBJPROP_SELECTABLE, true);   // draggable
        ObjectSetInteger(0, N_DASHBG, OBJPROP_HIDDEN,     true);
    }
    ObjectSetInteger(0, N_DASHBG, OBJPROP_XDISTANCE, g_panX);
    ObjectSetInteger(0, N_DASHBG, OBJPROP_YDISTANCE, g_panY);

    // ── Version label (top-right area of panel, light colour, small font) ──
    // Panel-relative: 330 px from panel left, 18 px from panel top (baseline).
    // Moves with the panel when dragged.
    {
        int vx = g_panX + (DASH_PAN_W - 40) * InpUIScale;
        int vy = g_panY + 18 * InpUIScale;
        if(ObjectFind(0, N_DASHV) < 0) ObjectCreate(0, N_DASHV, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, N_DASHV, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
        ObjectSetInteger(0, N_DASHV, OBJPROP_ANCHOR,     ANCHOR_LEFT_LOWER);
        ObjectSetInteger(0, N_DASHV, OBJPROP_XDISTANCE,  vx);
        ObjectSetInteger(0, N_DASHV, OBJPROP_YDISTANCE,  vy);
        ObjectSetString (0, N_DASHV, OBJPROP_FONT,       "Consolas");
        ObjectSetInteger(0, N_DASHV, OBJPROP_FONTSIZE,   8);
        ObjectSetString (0, N_DASHV, OBJPROP_TEXT,       EA_DASH_VER);
        ObjectSetInteger(0, N_DASHV, OBJPROP_COLOR,      C'210,220,235');
        ObjectSetInteger(0, N_DASHV, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, N_DASHV, OBJPROP_HIDDEN,     true);
    }

    // ── Colour palette ───────────────────────────────────────────
    color cGold  = C'255,200,60';    // cycle counts   — bright amber-gold
    color cBlue  = C'160,205,255';   // durations      — bright sky-blue
    color cGreen = C'80,235,140';    // above BE       — vivid emerald
    color cDim   = C'150,165,190';   // breakeven      — medium slate (was too dark)
    color cLabel = C'130,148,172';   // row labels     — visible on dark panel

    // ── 7 label rows (YDISTANCE measured from panel bottom) ──────
    // Row 0 — status / state  (shifted to y=169 to make room for the preview line)
    DashLabel(N_DASH0, 169, statText, statColor);

    // Row N — next upcoming event (session pause or news)
    // Priority: imminent session pause > imminent pre-block > informational news
    string nextText  = "";
    color  nextColor = cLabel;
    {
        string nextSess = "";
        long sessSecs = GetNextSessionPauseStart(nextSess);

        long newsBlock = -1, newsEvent = -1;
        string newsName = "", newsTime = "";
        bool hasNews = GetNextNewsInfo(newsBlock, newsEvent, newsName, newsTime);

        // Truncate name to 15 chars to fit the line.
        string shortNews = (hasNews && StringLen(newsName) > 15)
                           ? StringSubstr(newsName, 0, 15) + ".." : newsName;

        if(sessSecs >= 0 && (newsBlock < 0 || sessSecs <= newsBlock))
        {
            // Session pause is the most urgent event.
            nextText  = "\x25B8  \x23F8 " + nextSess + " pause  in " + FormatTimer(sessSecs);
            nextColor = C'251,191,36';   // amber
        }
        else if(hasNews && newsBlock >= 0 && newsBlock < (long)NEXT_NEWS_WARN_MIN * 60)
        {
            // Pre-block starts in < NEXT_NEWS_WARN_MIN → amber warning.
            // "▸ NEWS NFP 15:30  stops in 45m"
            nextText  = "\x25B8  NEWS " + shortNews + " " + newsTime
                        + "  stops in " + FormatTimer(newsBlock);
            nextColor = C'251,191,36';   // amber
        }
        else if(hasNews)
        {
            // News within NEXT_NEWS_SHOW_H hours — informational (dim).
            // "◦ NFP 15:30  in 3h05m"
            nextText  = "\x25E6  " + shortNews + " " + newsTime
                        + "  in " + FormatTimer(newsEvent);
            nextColor = cLabel;
        }
        else if(sessSecs >= 0)
        {
            // Session pause within warning window but less urgent — covered above.
            nextText  = "\x25B8  \x23F8 " + nextSess + " pause  in " + FormatTimer(sessSecs);
            nextColor = C'251,191,36';
        }
        // else: no upcoming events — line stays empty
    }
    // Empty string shows MT5 default "Label" text — use a space instead.
    DashLabel(N_DASHN, 145, (nextText == "" ? " " : nextText), nextColor);

    // Row B — box info
    DashLabel(N_DASHB, 121, boxText, cLabel);

    // Row 1 — today: cycles started + closed breakdown (BE / above BE)
    DashLabel(N_DASH1, 93,
        StringFormat("Today  %d  |  BE %d   >BE %d",
                     ciclosToday, beCyclesToday, aboveCyclesToday),
        cGold);

    // Row 2 — week: same breakdown
    DashLabel(N_DASH2, 69,
        StringFormat("Week   %d  |  BE %d   >BE %d",
                     ciclosWeek, beCyclesWeek, aboveCyclesWeek),
        cDim);

    // Row 3 — durations
    DashLabel(N_DASH3, 45,
        StringFormat("Duration  min %s \xB7 avg %s \xB7 max %s", sMin, sAvg, sMax),
        cBlue);

    // Row 4 — blank (freed from old separate breakeven rows)
    DashLabel(N_DASH4, 21, " ", cLabel);
}

//+------------------------------------------------------------------+
void UpdateVisuals()
{
    if(g_activeIdx < 0)
    {
        DeleteAllBoxes();
        g_activeSince=0; g_botUnstable=g_topUnstable=false; g_botTouchCount=g_topTouchCount=0; g_botInZone=g_topInZone=false;
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
    color cBody, cTop, cBot, cMid, cLabel;
    if(valid)
    {
        cBody   = C_MIDBODY;
        cTop    = !g_topUnstable ? C_EXTREME
                : (g_topTouchCount >= TOUCH_WARN_COUNT) ? C_OVERTOUCHED : C_UNSTABLE;
        cBot    = !g_botUnstable ? C_EXTREME
                : (g_botTouchCount >= TOUCH_WARN_COUNT) ? C_OVERTOUCHED : C_UNSTABLE;
        cMid    = C_MIDBAND;
        cLabel  = C_BORDER;
    }
    else
    {
        cBody = C_BELOWMIN; cTop = C_BELOWMIN;
        cBot  = C_BELOWMIN; cMid = C_BELOWMIN;    cLabel = clrDimGray;
    }
    BoxSet(N_MID,  bS,bH,     rTime,bL,    cBody,  true,  0);
    BoxSet(N_TOP,  bS,bH,     rTime,tb,    cTop,   true,  0);
    BoxSet(N_BOT,  bS,bb,     rTime,bL,    cBot,   true,  0);
    BoxSet(N_MBAND,bS,mid+zs, rTime,mid-zs,cMid,   true,  0);

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

    // Status and box info are now handled entirely by UpdateDashboard().
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
    g_botTouchCount = g_topTouchCount = 0;
    g_botInZone = g_topInZone = false;
    g_state = STATE_IDLE; g_tpFrozen = false; g_noNewCycles = false; g_prevBlockTime = 0; g_tradeBlockTime = 0;
    g_panX = -1; g_panY = -1; g_panDragged = false;
    g_dragging = false; g_prevLBtn = false;
    g_trade.SetExpertMagicNumber(MAGIC_NUMBER);
    g_prevState = STATE_IDLE; g_cycleOpenTime = 0; g_openTicketCount = 0;
    g_prevNews = g_prevSessionPause = g_prevForceClose = g_prevWebPause = false;
    g_prevTradingAllowed = true; ArrayInitialize(g_filterOnTimes, 0);
    g_lastSnapshotDate = 0; g_lastArchiveMonth = -1; g_sessionId = -1; g_currentBlockId = -1;

    // Restore user-dragged panel position from the previous session.
    if(GlobalVariableCheck("AUR_PAN_X") && GlobalVariableCheck("AUR_PAN_Y"))
    {
        g_panX       = (int)GlobalVariableGet("AUR_PAN_X");
        g_panY       = (int)GlobalVariableGet("AUR_PAN_Y");
        g_panDragged = true;
    }

    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);   // needed for drag detection
    CreateDashboardBitmap();   // build ARGB resource for the semi-transparent panel

    LoadNews();
    MqlDateTime d; TimeToStruct(LocalNow(), d); g_lastLoadDay = d.day_of_year;

    int total = iBars(Symbol(), Period());
    for(int shift = total-3; shift >= 1; shift--)
        ProcessBar(shift);
    UpdateVisuals();
    g_lastBarTime = iTime(Symbol(), Period(), 0);
    DBInit();
    DBLogSession();
    g_initialized = true;
    return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
    DBClose();
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
    ObjectsDeleteAll(0, N_PFX);
}

// Drag the dashboard panel with the mouse.
//
// OBJ_BITMAP_LABEL is a pixel-positioned overlay — MT5 never fires
// CHARTEVENT_OBJECT_DRAG or CHARTEVENT_OBJECT_CLICK reliably for it.
// We handle everything via CHARTEVENT_MOUSE_MOVE (enabled in OnInit via
// CHART_EVENT_MOUSE_MOVE=true):
//
//   lBtn just became true  +  cursor inside panel  →  start drag
//   lBtn still true        +  dragging             →  update position live
//   lBtn became false      +  dragging             →  stop, persist position
//
// g_prevLBtn tracks the previous button state so we only START a drag on
// the exact event where the button transitions false→true, preventing a
// spurious drag when the user scrolls the chart and the cursor enters the
// panel while the button is already held.
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id != CHARTEVENT_MOUSE_MOVE) return;

    int  mx   = (int)lparam;
    int  my   = (int)dparam;
    bool lBtn = ((int)StringToInteger(sparam) & 1) != 0;

    // ── Detect drag start: button pressed for the first time inside panel ──
    if(lBtn && !g_prevLBtn && !g_dragging)
    {
        if(mx >= g_panX && mx < g_panX + DASH_PAN_W * InpUIScale &&
           my >= g_panY && my < g_panY + DASH_PAN_H * InpUIScale)
        {
            g_dragging   = true;
            g_panDragged = true;
            g_dragOffX   = mx - g_panX;
            g_dragOffY   = my - g_panY;
        }
    }

    // ── Move panel while dragging ──────────────────────────────────
    if(g_dragging)
    {
        if(!lBtn)
        {
            g_dragging = false;
            GlobalVariableSet("AUR_PAN_X", (double)g_panX);
            GlobalVariableSet("AUR_PAN_Y", (double)g_panY);
        }
        else
        {
            long cW = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
            long cH = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
            g_panX = mx - g_dragOffX;
            g_panY = my - g_dragOffY;
            if(g_panX < 0) g_panX = 0;
            if(g_panY < 0) g_panY = 0;
            if(g_panX + DASH_PAN_W * InpUIScale > (int)cW)
                g_panX = (int)cW - DASH_PAN_W * InpUIScale;
            if(g_panY + DASH_PAN_H * InpUIScale > (int)cH)
                g_panY = (int)cH - DASH_PAN_H * InpUIScale;
            UpdateDashboard();
            ChartRedraw(0);
        }
    }

    g_prevLBtn = lBtn;
}

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
        DBArchiveAndPrune();
    }
    UpdateVisuals();
    ManageTrade();
}
