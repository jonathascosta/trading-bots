//+------------------------------------------------------------------+
//|  RangeBreaker.mq5                                                |
//|  Copyright (c) 2025-2026, Jonathas Costa                         |
//|  github.com/jonathas/trading-bots                                |
//|                                                                  |
//|  MIT License - free to use and modify, keeping this              |
//|  header and copyright notice in all copies.                      |
//+------------------------------------------------------------------+
#property copyright "Jonathas Costa"
#property link      "https://github.com/jonathas/trading-bots"

#property version   "1.33"
#property description "Operates on session range breakouts with multiple entry modes."

//--- Include necessary libraries
#include <Trade\Trade.mqh>


//==================================================================
//== INPUT PARAMETERS
//==================================================================

//--- Session 1 Parameters
input group             "========== SESSION 1 SETTINGS ==========";
input bool              Session1_Enable      = true;            // Enable Session 1
input string            Session1_Name        = "Sydney";        // Session 1 Name
input string            Session1_StartTime   = "01:00";         // Session 1 Start Time (HH:MM)
input string            Session1_EndTime     = "09:00";         // Session 1 End Time (HH:MM)
input color             Session1_Color       = clrDodgerBlue;   // Session 1 Candle Color
input ENUM_TIMEFRAMES   Session1_Timeframe   = PERIOD_M5;       // Session 1 Timeframe
input int               Session1_CandleCount = 4;               // Session 1 Number of Candles

//--- Session 2 Parameters
input group             "========== SESSION 2 SETTINGS ==========";
input bool              Session2_Enable      = true;            // Enable Session 2
input string            Session2_Name        = "Tokyo";         // Session 2 Name
input string            Session2_StartTime   = "03:00";         // Session 2 Start Time (HH:MM)
input string            Session2_EndTime     = "12:00";         // Session 2 End Time (HH:MM)
input color             Session2_Color       = clrDeepPink;     // Session 2 Candle Color
input ENUM_TIMEFRAMES   Session2_Timeframe   = PERIOD_M5;       // Session 2 Timeframe
input int               Session2_CandleCount = 4;               // Session 2 Number of Candles

//--- Session 3 Parameters
input group             "========== SESSION 3 SETTINGS ==========";
input bool              Session3_Enable      = true;            // Enable Session 3
input string            Session3_Name        = "London";        // Session 3 Name
input string            Session3_StartTime   = "10:00";         // Session 3 Start Time (HH:MM)
input string            Session3_EndTime     = "19:00";         // Session 3 End Time (HH:MM)
input color             Session3_Color       = clrAqua;         // Session 3 Candle Color
input ENUM_TIMEFRAMES   Session3_Timeframe   = PERIOD_M5;       // Session 3 Timeframe
input int               Session3_CandleCount = 4;               // Session 3 Number of Candles

//--- Session 4 Parameters
input group             "========== SESSION 4 SETTINGS ==========";
input bool              Session4_Enable      = true;            // Enable Session 4
input string            Session4_Name        = "New York";      // Session 4 Name
input string            Session4_StartTime   = "15:00";         // Session 4 Start Time (HH:MM)
input string            Session4_EndTime     = "00:00";         // Session 4 End Time (HH:MM)
input color             Session4_Color       = clrGold;         // Session 4 Candle Color
input ENUM_TIMEFRAMES   Session4_Timeframe   = PERIOD_M5;       // Session 4 Timeframe
input int               Session4_CandleCount = 4;               // Session 4 Number of Candles

//--- Session 5 Parameters
input group             "========== SESSION 5 SETTINGS ==========";
input bool              Session5_Enable      = true;            // Enable Session 5
input string            Session5_Name        = "NYSE";          // Session 5 Name
input string            Session5_StartTime   = "16:30";         // Session 5 Start Time (HH:MM)
input string            Session5_EndTime     = "23:00";         // Session 5 End Time (HH:MM)
input color             Session5_Color       = clrOrchid;       // Session 5 Candle Color
input ENUM_TIMEFRAMES   Session5_Timeframe   = PERIOD_M5;       // Session 5 Timeframe
input int               Session5_CandleCount = 4;               // Session 5 Number of Candles

//--- General Settings
input group             "========== GENERAL SETTINGS ==========";
input int               LineWidth          = 1;               // Line Width
input bool              ShowLabels         = true;            // Show Price Labels on Lines

//--- GUI Dashboard Settings
input group             "========== GUI DASHBOARD ==========";
input bool              ShowGUI            = true;            // Show GUI Dashboard
input int               GUI_X              = 20;              // GUI X Position
input int               GUI_Y              = 50;              // GUI Y Position
input color             GUI_BackgroundColor= C'40,40,40';      // GUI Background Color
input color             GUI_TextColor      = clrWhite;          // GUI Text Color
input int               GUI_FontSize       = 9;               // GUI Font Size

//--- Trading Settings
input group             "========== TRADING SETTINGS ==========";
input bool              TradeOnMonday      = true;            // Trade on Monday
input bool              TradeOnTuesday     = true;            // Trade on Tuesday
input bool              TradeOnWednesday   = true;            // Trade on Wednesday
input bool              TradeOnThursday    = true;            // Trade on Thursday
input bool              TradeOnFriday      = true;            // Trade on Friday
input bool              CancelPendingOrdersIfNewSessionStarts = true; // Cancel old trades on new session
input bool              WaitForConfirmation= false;           // Wait for Candle Close Confirmation
input ENUM_TIMEFRAMES   ConfirmationCandle = PERIOD_M1;       // Timeframe for Confirmation Candle
input bool              EnableBuyTrading   = true;            // Enable Buy Trades
input bool              EnableSellTrading  = true;            // Enable Sell Trades
input double            RiskPercent        = 0.5;             // Risk Percentage per Trade
input double            MinRange           = 0.0;             // Minimum Session Range to trade
input double            MaxRange           = 1000.0;          // Maximum Session Range to trade
input int               MagicNumber        = 123456;          // Magic Number for Orders
input string            TradeComment       = "RangeBreaker";    // Order Comment


//==================================================================
//== GLOBAL VARIABLES & STRUCTS
//==================================================================

struct SessionData
{
   bool              enabled;
   string            name;
   string            start_time;
   string            end_time;
   color             candle_color;
   ENUM_TIMEFRAMES   timeframe;
   int               candle_count;
   bool              session_active;
   bool              session_completed;
   datetime          session_start_dt;
   datetime          session_end_dt;
   double            session_high;
   double            session_low;
   double            initial_range;

   // Buy order fields
   double            buy_entry;
   double            buy_take_profit;
   double            buy_stop_loss;
   bool              buy_trade_placed;
   ulong             buy_order_ticket;
   ulong             buy_position_id;

   // Sell order fields
   double            sell_entry;
   double            sell_take_profit;
   double            sell_stop_loss;
   bool              sell_trade_placed;
   ulong             sell_order_ticket;
   ulong             sell_position_id;

   string            high_line_name;
   string            low_line_name;
   string            buy_entry_line_name;
   string            sell_entry_line_name;

   // Trading levels
   int               candles_processed;
};

struct SessionStats
{
   // Buy order statistics
   int               buy_orders_opened;
   int               buy_orders_tp;
   int               buy_orders_sl;
   double            buy_total_profit;

   // Sell order statistics
   int               sell_orders_opened;
   int               sell_orders_tp;
   int               sell_orders_sl;
   double            sell_total_profit;

   // Combined statistics
   double            total_range;
   int               range_count;
   double            avg_range;
};

SessionData sessions[5];
SessionStats stats[5];
datetime last_check_time = 0;
datetime last_reset_date = 0;
datetime ea_start_time = 0;
datetime last_bar_time = 0; // For new bar detection
CTrade trade;


//==================================================================
//== HELPER & SETUP FUNCTIONS
//==================================================================

bool ValidateInputs()
{
   bool one_enabled = Session1_Enable || Session2_Enable || Session3_Enable || Session4_Enable || Session5_Enable;
   if(!one_enabled) { Print("Error: At least one session must be enabled"); return false; }
   if(Session1_Enable && (Session1_CandleCount < 1 || Session1_CandleCount > 100)) return false;
   if(Session2_Enable && (Session2_CandleCount < 1 || Session2_CandleCount > 100)) return false;
   if(Session3_Enable && (Session3_CandleCount < 1 || Session3_CandleCount > 100)) return false;
   if(Session4_Enable && (Session4_CandleCount < 1 || Session4_CandleCount > 100)) return false;
   if(Session5_Enable && (Session5_CandleCount < 1 || Session5_CandleCount > 100)) return false;
   if(Session1_Enable && (!IsValidTimeFormat(Session1_StartTime) || !IsValidTimeFormat(Session1_EndTime))) return false;
   if(Session2_Enable && (!IsValidTimeFormat(Session2_StartTime) || !IsValidTimeFormat(Session2_EndTime))) return false;
   if(Session3_Enable && (!IsValidTimeFormat(Session3_StartTime) || !IsValidTimeFormat(Session3_EndTime))) return false;
   if(Session4_Enable && (!IsValidTimeFormat(Session4_StartTime) || !IsValidTimeFormat(Session4_EndTime))) return false;
   if(Session5_Enable && (!IsValidTimeFormat(Session5_StartTime) || !IsValidTimeFormat(Session5_EndTime))) return false;
   if(RiskPercent <= 0 || RiskPercent > 100) return false;
   if(MinRange < 0 || MaxRange < 0 || MinRange > MaxRange) return false;
   if(MagicNumber <= 0) return false;

   // NEW: Validate ConfirmationCandle timeframe
   if(WaitForConfirmation)
   {
      ENUM_TIMEFRAMES session_tfs[] = {Session1_Timeframe, Session2_Timeframe, Session3_Timeframe, Session4_Timeframe, Session5_Timeframe};
      bool session_enables[] = {Session1_Enable, Session2_Enable, Session3_Enable, Session4_Enable, Session5_Enable};
      for(int i=0; i<5; i++)
      {
         if(session_enables[i] && ConfirmationCandle > session_tfs[i])
         {
            Print("Error: ConfirmationCandle timeframe (", EnumToString(ConfirmationCandle),
                  ") cannot be greater than Session ", i+1, " timeframe (", EnumToString(session_tfs[i]), ").");
            return false;
         }
      }
   }

   return true;
}

bool IsValidTimeFormat(string time_str)
{
   if(StringLen(time_str) != 5 || StringGetCharacter(time_str, 2) != ':') return false;
   string parts[];
   if(StringSplit(time_str, ':', parts) != 2) return false;
   int hour = (int)StringToInteger(parts[0]);
   int minute = (int)StringToInteger(parts[1]);
   return (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59);
}

int FindNextActiveSession(int current_session_index)
{
    bool session_enables[] = {Session1_Enable, Session2_Enable, Session3_Enable, Session4_Enable, Session5_Enable};

    // Search from the next session to the end
    for(int i = current_session_index + 1; i < 5; i++)
    {
        if(session_enables[i]) return i;
    }

    // Wrap around and search from the beginning
    for(int i = 0; i < current_session_index; i++)
    {
        if(session_enables[i]) return i;
    }

    return -1; // No other active session found
}

datetime GetTimeFromString(string time_str)
{
    datetime now = TimeCurrent();
    MqlDateTime dt_struct;
    TimeToStruct(now, dt_struct);

    // Reset time part to 00:00:00 to get the start of the current day
    dt_struct.hour = 0;
    dt_struct.min = 0;
    dt_struct.sec = 0;
    datetime today_start = StructToTime(dt_struct);

    // Parse time string
    string parts[];
    StringSplit(time_str, ':', parts);
    int hour = (int)StringToInteger(parts[0]);
    int minute = (int)StringToInteger(parts[1]);

    // Add the hours and minutes to the start of today
    return today_start + (hour * 3600) + (minute * 60);
}

bool IsTradingDayAllowed()
{
   MqlDateTime dt;
   TimeCurrent(dt); // Get current server time

   switch(dt.day_of_week)
   {
      case 1: // Monday
         return(TradeOnMonday);
      case 2: // Tuesday
         return(TradeOnTuesday);
      case 3: // Wednesday
         return(TradeOnWednesday);
      case 4: // Thursday
         return(TradeOnThursday);
      case 5: // Friday
         return(TradeOnFriday);
   }
   return(false); // Saturday and Sunday
}

void CleanupGUI()
{
   ObjectsDeleteAll(0, "EA_GUI_");
}

void CleanupObjects()
{
   for(int i = 0; i < 5; i++)
   {
      ObjectDelete(0, sessions[i].high_line_name);
      ObjectDelete(0, sessions[i].low_line_name);
      ObjectDelete(0, sessions[i].high_line_name + "_Label");
      ObjectDelete(0, sessions[i].low_line_name + "_Label");
      ObjectDelete(0, sessions[i].buy_entry_line_name);
      ObjectDelete(0, sessions[i].sell_entry_line_name);
   }
   CleanupGUI();
   Print("All EA objects cleaned up");
   ChartRedraw(0);
}


//==================================================================
//== GUI DASHBOARD FUNCTIONS
//==================================================================

void CreateGUILabel(string name, string text, int x, int y, int font_size, color text_color, ENUM_ANCHOR_POINT anchor=ANCHOR_LEFT)
{
   ObjectDelete(0, name);
   if(ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, "Courier New");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
      ObjectSetInteger(0, name, OBJPROP_COLOR, text_color);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
}

void UpdateGUI()
{
   if(!ShowGUI) return;
   CreateGUIBackground();
   CreateGUIContent();
   ChartRedraw(0);
}

void CreateGUIBackground()
{
   string bg_name = "EA_GUI_Background";
   int enabled_sessions_count = 0;
   if(Session1_Enable) enabled_sessions_count++; if(Session2_Enable) enabled_sessions_count++; if(Session3_Enable) enabled_sessions_count++;
   if(Session4_Enable) enabled_sessions_count++; if(Session5_Enable) enabled_sessions_count++;

   int panel_width = 420; // Increased width for better spacing
   int panel_height = 60 + (enabled_sessions_count * 20) + 45;

   ObjectDelete(0, bg_name);
   if(ObjectCreate(0, bg_name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, bg_name, OBJPROP_XDISTANCE, GUI_X); ObjectSetInteger(0, bg_name, OBJPROP_YDISTANCE, GUI_Y);
      ObjectSetInteger(0, bg_name, OBJPROP_XSIZE, panel_width); ObjectSetInteger(0, bg_name, OBJPROP_YSIZE, panel_height);
      ObjectSetInteger(0, bg_name, OBJPROP_BGCOLOR, GUI_BackgroundColor); ObjectSetInteger(0, bg_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg_name, OBJPROP_CORNER, CORNER_LEFT_UPPER); ObjectSetInteger(0, bg_name, OBJPROP_COLOR, clrDarkGray);
   }
}

void DrawTableRow(string id, int y, string s_name, int trades, int wins, int losses, double pl, double avg_range, color text_color)
{
    int x = GUI_X + 10;
    CreateGUILabel("EA_GUI_"+id+"_Name", s_name, x, y, GUI_FontSize, text_color, ANCHOR_LEFT);
    CreateGUILabel("EA_GUI_"+id+"_Trades", IntegerToString(trades), x + 140, y, GUI_FontSize, text_color, ANCHOR_RIGHT);
    CreateGUILabel("EA_GUI_"+id+"_Wins", IntegerToString(wins), x + 200, y, GUI_FontSize, text_color, ANCHOR_RIGHT);
    CreateGUILabel("EA_GUI_"+id+"_Losses", IntegerToString(losses), x + 260, y, GUI_FontSize, text_color, ANCHOR_RIGHT);
    CreateGUILabel("EA_GUI_"+id+"_PL", DoubleToString(pl, 2), x + 330, y, GUI_FontSize, text_color, ANCHOR_RIGHT);
    CreateGUILabel("EA_GUI_"+id+"_AvgRange", DoubleToString(avg_range, _Digits), x + 400, y, GUI_FontSize, text_color, ANCHOR_RIGHT);
}

void CreateGUIContent()
{
   int y = GUI_Y + 10;
   int lh = 18; // Line height
   int x = GUI_X + 10;

   // --- Main Title and Runtime ---
   CreateGUILabel("EA_GUI_Title", "Range Breaker EA Dashboard", x, y, GUI_FontSize + 1, GUI_TextColor, ANCHOR_LEFT);
   datetime rt = TimeCurrent() - ea_start_time;
   string rt_txt = "Runtime: " + IntegerToString((int)(rt / 3600)) + "h " + IntegerToString((int)((rt % 3600) / 60)) + "m";
   CreateGUILabel("EA_GUI_Runtime", rt_txt, x + 400, y, GUI_FontSize, GUI_TextColor, ANCHOR_RIGHT);
   y += lh + 2;

   // --- Table Header ---
   CreateGUILabel("EA_GUI_H_Sep1", "----------------------------------------------------------", x, y, GUI_FontSize, clrDarkGray);
   y += lh;
   CreateGUILabel("EA_GUI_H_Name",    "SESSION",   x,       y, GUI_FontSize, GUI_TextColor, ANCHOR_LEFT);
   CreateGUILabel("EA_GUI_H_Trades",  "TRADES",    x + 140, y, GUI_FontSize, GUI_TextColor, ANCHOR_RIGHT);
   CreateGUILabel("EA_GUI_H_Wins",    "WINS",      x + 200, y, GUI_FontSize, GUI_TextColor, ANCHOR_RIGHT);
   CreateGUILabel("EA_GUI_H_Losses",  "LOSSES",    x + 260, y, GUI_FontSize, GUI_TextColor, ANCHOR_RIGHT);
   CreateGUILabel("EA_GUI_H_PL",      "P/L ($)",   x + 330, y, GUI_FontSize, GUI_TextColor, ANCHOR_RIGHT);
   CreateGUILabel("EA_GUI_H_AvgRng",  "AVG RNG",   x + 400, y, GUI_FontSize, GUI_TextColor, ANCHOR_RIGHT);
   y += lh;
   CreateGUILabel("EA_GUI_H_Sep2", "----------------------------------------------------------", x, y, GUI_FontSize, clrDarkGray);
   y += lh;

   // --- Table Data Rows ---
   int g_trades=0, g_wins=0, g_losses=0, g_range_c=0;
   double g_pl=0, g_range_t=0;

   for(int i = 0; i < 5; i++)
   {
      if(!sessions[i].enabled) continue;

      int trades = stats[i].buy_orders_opened + stats[i].sell_orders_opened;
      int wins = stats[i].buy_orders_tp + stats[i].sell_orders_tp;
      int losses = stats[i].buy_orders_sl + stats[i].sell_orders_sl;
      double pl = stats[i].buy_total_profit + stats[i].sell_total_profit;

      DrawTableRow(sessions[i].name, y, sessions[i].name, trades, wins, losses, pl, stats[i].avg_range, sessions[i].candle_color);
      y += lh;

      g_trades += trades;
      g_wins += wins;
      g_losses += losses;
      g_pl += pl;
      g_range_t += stats[i].total_range;
      g_range_c += stats[i].range_count;
   }

   // --- Table Footer (Total) ---
   CreateGUILabel("EA_GUI_F_Sep1", "----------------------------------------------------------", x, y, GUI_FontSize, clrDarkGray);
   y += lh;
   double avg_range_total = (g_range_c > 0) ? g_range_t / g_range_c : 0.0;
   DrawTableRow("Total", y, "TOTAL", g_trades, g_wins, g_losses, g_pl, avg_range_total, GUI_TextColor);
   y += lh;
   CreateGUILabel("EA_GUI_F_Sep2", "----------------------------------------------------------", x, y, GUI_FontSize, clrDarkGray);
}


//==================================================================
//== MQL5 MAIN FUNCTIONS
//==================================================================

int OnInit()
{
   Print("Range Breaker EA v3.03 initialized successfully");
   ea_start_time = TimeCurrent();

   if(!ValidateInputs())
   {
      Print("Invalid input parameters detected. EA initialization failed.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   InitializeSessions();
   InitializeStatistics();
   CleanupObjects();

   if(ShowGUI) UpdateGUI();

   Print("Entry Mode: ", WaitForConfirmation ? "On Candle Confirmation" : "Pending Orders");
   if(WaitForConfirmation) Print("Confirmation Timeframe: ", EnumToString(ConfirmationCandle));
   Print("Magic number: ", MagicNumber);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   CleanupObjects();
   Print("Range Breaker EA deinitialized");
}

void OnTick()
{
   datetime current_time = TimeCurrent();

   // --- Check for new bar to run confirmation logic ---
   if(last_bar_time != iTime(_Symbol, ConfirmationCandle, 0))
   {
      last_bar_time = iTime(_Symbol, ConfirmationCandle, 0);
      if(WaitForConfirmation)
      {
         CheckForConfirmationEntry();
      }
   }

   // --- Run session logic once per minute ---
   if(current_time - last_check_time >= 60)
   {
      CheckDailyReset();
      CheckSessions();
      last_check_time = current_time;
   }

   // --- Update GUI ---
   if(ShowGUI) UpdateGUI();
}


//==================================================================
//== SESSION & CANDLE LOGIC
//==================================================================

void CheckDailyReset()
{
   datetime current_time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(current_time, dt);
   datetime current_date = StructToTime(dt) - (dt.hour * 3600 + dt.min * 60 + dt.sec);

   if(last_reset_date != current_date)
   {
      ResetDailySessionData();
      last_reset_date = current_date;
      Print("New trading day detected. Daily session data reset.");
   }
}

void ResetDailySessionData()
{
   for(int i = 0; i < 5; i++)
   {
      sessions[i].session_active = false;
      sessions[i].session_completed = false;
      sessions[i].session_high = 0;
      sessions[i].session_low = 0;
      sessions[i].initial_range = 0;
      sessions[i].buy_entry = 0;
      sessions[i].buy_take_profit = 0;
      sessions[i].buy_stop_loss = 0;
      sessions[i].buy_trade_placed = false;
      sessions[i].buy_order_ticket = 0;
      sessions[i].buy_position_id = 0;
      sessions[i].sell_entry = 0;
      sessions[i].sell_take_profit = 0;
      sessions[i].sell_stop_loss = 0;
      sessions[i].sell_trade_placed = false;
      sessions[i].sell_order_ticket = 0;
      sessions[i].sell_position_id = 0;
      sessions[i].candles_processed = 0;

      ObjectDelete(0, sessions[i].high_line_name);
      ObjectDelete(0, sessions[i].low_line_name);
      ObjectDelete(0, sessions[i].high_line_name + "_Label");
      ObjectDelete(0, sessions[i].low_line_name + "_Label");
      ObjectDelete(0, sessions[i].buy_entry_line_name);
      ObjectDelete(0, sessions[i].sell_entry_line_name);
   }
   Print("Daily session tracking data has been reset.");
}

void InitializeSessions()
{
   sessions[0].enabled = Session1_Enable; sessions[0].name = Session1_Name; sessions[0].start_time = Session1_StartTime; sessions[0].end_time = Session1_EndTime; sessions[0].candle_color = Session1_Color; sessions[0].timeframe = Session1_Timeframe; sessions[0].candle_count = Session1_CandleCount;
   sessions[1].enabled = Session2_Enable; sessions[1].name = Session2_Name; sessions[1].start_time = Session2_StartTime; sessions[1].end_time = Session2_EndTime; sessions[1].candle_color = Session2_Color; sessions[1].timeframe = Session2_Timeframe; sessions[1].candle_count = Session2_CandleCount;
   sessions[2].enabled = Session3_Enable; sessions[2].name = Session3_Name; sessions[2].start_time = Session3_StartTime; sessions[2].end_time = Session3_EndTime; sessions[2].candle_color = Session3_Color; sessions[2].timeframe = Session3_Timeframe; sessions[2].candle_count = Session3_CandleCount;
   sessions[3].enabled = Session4_Enable; sessions[3].name = Session4_Name; sessions[3].start_time = Session4_StartTime; sessions[3].end_time = Session4_EndTime; sessions[3].candle_color = Session4_Color; sessions[3].timeframe = Session4_Timeframe; sessions[3].candle_count = Session4_CandleCount;
   sessions[4].enabled = Session5_Enable; sessions[4].name = Session5_Name; sessions[4].start_time = Session5_StartTime; sessions[4].end_time = Session5_EndTime; sessions[4].candle_color = Session5_Color; sessions[4].timeframe = Session5_Timeframe; sessions[4].candle_count = Session5_CandleCount;

   for(int i = 0; i < 5; i++)
   {
      sessions[i].high_line_name = "Session" + IntegerToString(i+1) + "_High";
      sessions[i].low_line_name = "Session" + IntegerToString(i+1) + "_Low";
      sessions[i].buy_entry_line_name = "Session" + IntegerToString(i+1) + "_BuyEntry";
      sessions[i].sell_entry_line_name = "Session" + IntegerToString(i+1) + "_SellEntry";
      sessions[i].buy_position_id = 0;
      sessions[i].sell_position_id = 0;
   }
}

void InitializeStatistics()
{
   for(int i = 0; i < 5; i++)
   {
      stats[i].buy_orders_opened = 0; stats[i].sell_orders_opened = 0;
      stats[i].buy_orders_tp = 0; stats[i].sell_orders_tp = 0;
      stats[i].buy_orders_sl = 0; stats[i].sell_orders_sl = 0;
      stats[i].buy_total_profit = 0.0; stats[i].sell_total_profit = 0.0;
      stats[i].total_range = 0.0; stats[i].range_count = 0; stats[i].avg_range = 0.0;
   }
   Print("Historical statistics initialized for all sessions.");
}

void CheckSessions()
{
   for(int i = 0; i < 5; i++)
   {
      if(!sessions[i].enabled) continue;
      CheckSessionStatus(i);
      if(sessions[i].session_active && !sessions[i].session_completed) ProcessSessionCandles(i);
   }
}

void CheckSessionStatus(int session_index)
{
   datetime current_time = TimeCurrent();
   MqlDateTime dt; TimeToStruct(current_time, dt);
   string start_parts[]; StringSplit(sessions[session_index].start_time, ':', start_parts);
   string end_parts[]; StringSplit(sessions[session_index].end_time, ':', end_parts);
   int start_hour = (int)StringToInteger(start_parts[0]); int start_minute = (int)StringToInteger(start_parts[1]);
   int end_hour = (int)StringToInteger(end_parts[0]); int end_minute = (int)StringToInteger(end_parts[1]);
   datetime today = StructToTime(dt) - (dt.hour * 3600 + dt.min * 60 + dt.sec);
   datetime session_start = today + start_hour * 3600 + start_minute * 60;
   datetime session_end = today + end_hour * 3600 + end_minute * 60;
   if(session_end < session_start) { if(current_time < session_end + (24*3600)/2) session_start -= 24*3600; else session_end += 24*3600; }
   if(!sessions[session_index].session_active && current_time >= session_start && current_time < session_end) StartSession(session_index, session_start, session_end);
   if(sessions[session_index].session_active && current_time >= session_end) EndSession(session_index);
}

void StartSession(int session_index, datetime start_time, datetime end_time)
{
   ENUM_TIMEFRAMES tf = sessions[session_index].timeframe;
   int period_seconds = PeriodSeconds(tf);
   datetime aligned_start = (start_time / period_seconds) * period_seconds;
   sessions[session_index].session_active = true;
   sessions[session_index].session_completed = false;
   sessions[session_index].session_start_dt = aligned_start;
   sessions[session_index].session_end_dt = end_time;
   datetime period_end = aligned_start + (sessions[session_index].candle_count * period_seconds);
   Print("Session ", session_index + 1, " (", sessions[session_index].name, ") started. Analysis: ", TimeToString(aligned_start), " to ", TimeToString(period_end));
}

void EndSession(int session_index)
{
   sessions[session_index].session_active = false;
   sessions[session_index].session_completed = true;
   if(sessions[session_index].session_high > 0) DrawHighLowLines(session_index);
   Print("Session ", session_index + 1, " ended.");
}

void ProcessSessionCandles(int session_index)
{
   if(sessions[session_index].candles_processed >= sessions[session_index].candle_count) return;

   ENUM_TIMEFRAMES tf = sessions[session_index].timeframe;
   int period_seconds = PeriodSeconds(tf);
   datetime start_time = sessions[session_index].session_start_dt;
   datetime end_time = start_time + (sessions[session_index].candle_count * period_seconds);

   if(TimeCurrent() < end_time) return; // Wait until the analysis period is fully over

   MqlRates rates[];
   // Use CopyRates by time range for better accuracy, especially around midnight
   int copied = CopyRates(_Symbol, tf, start_time, end_time, rates);

   if(copied < sessions[session_index].candle_count)
   {
      Print("Warning for ", sessions[session_index].name, ": Could not copy all required candles. Got ", copied, ", expected ", sessions[session_index].candle_count);
      if(copied <= 0) return; // If no bars were copied, we can't proceed
   }

   ProcessValidatedCandles(session_index, rates, copied);
}

void ProcessValidatedCandles(int session_index, MqlRates &rates[], int count)
{
   sessions[session_index].session_high = 0; sessions[session_index].session_low = DBL_MAX;
   for(int i = 0; i < count; i++)
   {
      if(rates[i].high > sessions[session_index].session_high) sessions[session_index].session_high = rates[i].high;
      if(rates[i].low < sessions[session_index].session_low) sessions[session_index].session_low = rates[i].low;
   }
   sessions[session_index].candles_processed = count;

   CalculateTradingLevels(session_index);

   if(CancelPendingOrdersIfNewSessionStarts)
   {
      InvalidatePreviousOpportunities(session_index);
   }

   DrawHighLowLines(session_index);

   if(sessions[session_index].initial_range >= MinRange && sessions[session_index].initial_range <= MaxRange)
   {
      if(!WaitForConfirmation)
      {
         if(EnableBuyTrading && !sessions[session_index].buy_trade_placed) PlaceBuyOrder(session_index);
         if(EnableSellTrading && !sessions[session_index].sell_trade_placed) PlaceSellOrder(session_index);
      }
      else
      {
         Print("Session ", session_index + 1, " range defined. Waiting for candle confirmation.");
      }
   }
   else
   {
      Print("Trading for Session ", session_index + 1, " skipped: Initial Range (",
            DoubleToString(sessions[session_index].initial_range, _Digits), ") is outside Min/Max limits.");
      sessions[session_index].buy_trade_placed = true;
      sessions[session_index].sell_trade_placed = true;
   }
}


//==================================================================
//== TRADING FUNCTIONS
//==================================================================

void CalculateTradingLevels(int session_index)
{
   sessions[session_index].initial_range = sessions[session_index].session_high - sessions[session_index].session_low;
   stats[session_index].total_range += sessions[session_index].initial_range;
   stats[session_index].range_count++;
   stats[session_index].avg_range = stats[session_index].total_range / stats[session_index].range_count;
   sessions[session_index].buy_entry = sessions[session_index].session_high + sessions[session_index].initial_range;
   sessions[session_index].buy_take_profit = sessions[session_index].buy_entry + (sessions[session_index].initial_range * 2);
   sessions[session_index].buy_stop_loss = sessions[session_index].session_low - (sessions[session_index].initial_range / 2);
   sessions[session_index].sell_entry = sessions[session_index].session_low - sessions[session_index].initial_range;
   sessions[session_index].sell_take_profit = sessions[session_index].sell_entry - (sessions[session_index].initial_range * 2);
   sessions[session_index].sell_stop_loss = sessions[session_index].session_high + (sessions[session_index].initial_range / 2);
}

void PlaceBuyOrder(int session_index)
{
   double buy_entry = NormalizeDouble(sessions[session_index].buy_entry, _Digits);
   double take_profit = NormalizeDouble(sessions[session_index].buy_take_profit, _Digits);
   double stop_loss = NormalizeDouble(sessions[session_index].buy_stop_loss, _Digits);

   double volume = CalculateVolume(buy_entry, stop_loss);
   if(volume <= 0)
   {
      Print("Volume calculation failed for Buy order, Session ", session_index + 1);
      return;
   }

   string comment = TradeComment + "_S" + IntegerToString(session_index + 1) + "_BUY";
   if(trade.BuyStop(volume, buy_entry, _Symbol, stop_loss, take_profit, ORDER_TIME_GTC, 0, comment))
   {
      sessions[session_index].buy_trade_placed = true;
      sessions[session_index].buy_order_ticket = trade.ResultOrder();
      Print("Buy Stop PLACED for Session ", session_index + 1, " | Vol: ", volume, " | Ticket: ", trade.ResultOrder());
   }
}

double CalculateVolume(double entry_price, double stop_loss_price)
{
   //--- Get account and symbol info
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volume_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   //--- Determine order type for profit calculation
   ENUM_ORDER_TYPE order_type = (entry_price > stop_loss_price) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   //--- Calculate potential loss for a 1.0 lot trade using OrderCalcProfit
   double profit_calc = 0;
   if(!OrderCalcProfit(order_type, _Symbol, 1.0, entry_price, stop_loss_price, profit_calc))
   {
      Print("OrderCalcProfit failed. Error: ", GetLastError());
      return 0.0;
   }

   double loss_per_lot = MathAbs(profit_calc);
   if(loss_per_lot <= 0)
   {
      Print("Calculated loss per lot is zero or negative. Cannot calculate volume.");
      return 0.0;
   }

   //--- Calculate risk amount and the ideal volume
   double risk_amount = balance * (RiskPercent / 100.0);
   double volume = risk_amount / loss_per_lot;

   //--- Normalization and Safety Checks ---
   volume = MathFloor(volume / volume_step) * volume_step;

   if(volume < min_volume)
      volume = min_volume;
   if(volume > max_volume)
      volume = max_volume;

   //--- Margin Check
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double required_margin = 0;
   if(!OrderCalcMargin(order_type, _Symbol, volume, entry_price, required_margin))
   {
      Print("Failed to calculate margin for volume ", volume, ". Error: ", GetLastError());
      return 0;
   }
   if(required_margin > free_margin)
   {
      Print("Not enough free margin for volume ", volume, ". Required: ", required_margin, ", Free: ", free_margin);
      return 0;
   }

   return volume;
}

void PlaceSellOrder(int session_index)
{
   double sell_entry = NormalizeDouble(sessions[session_index].sell_entry, _Digits);
   double take_profit = NormalizeDouble(sessions[session_index].sell_take_profit, _Digits);
   double stop_loss = NormalizeDouble(sessions[session_index].sell_stop_loss, _Digits);

   double volume = CalculateVolume(sell_entry, stop_loss);
   if(volume <= 0)
   {
      Print("Volume calculation failed for Sell order, Session ", session_index + 1);
      return;
   }

   string comment = TradeComment + "_S" + IntegerToString(session_index + 1) + "_SELL";
   if(trade.SellStop(volume, sell_entry, _Symbol, stop_loss, take_profit, ORDER_TIME_GTC, 0, comment))
   {
      sessions[session_index].sell_trade_placed = true;
      sessions[session_index].sell_order_ticket = trade.ResultOrder();
      Print("Sell Stop PLACED for Session ", session_index + 1, " | Vol: ", volume, " | Ticket: ", trade.ResultOrder());
   }
}

void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) ProcessDeal(trans.deal);
}

void ProcessDeal(ulong deal_ticket)
{
   if(!HistoryDealSelect(deal_ticket) || HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) != MagicNumber) return;

   long deal_entry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
   ulong position_id = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);

   // --- A: Position was just OPENED ---
   if(deal_entry == DEAL_ENTRY_IN)
   {
      string deal_comment = HistoryDealGetString(deal_ticket, DEAL_COMMENT);
      int session_index = -1; bool is_buy_trade = false;
      for(int i = 0; i < 5; i++) {
         if(StringFind(deal_comment, "_S" + IntegerToString(i + 1) + "_BUY") >= 0) { session_index = i; is_buy_trade = true; break; }
         if(StringFind(deal_comment, "_S" + IntegerToString(i + 1) + "_SELL") >= 0) { session_index = i; is_buy_trade = false; break; }
      }
      if(session_index != -1) {
         Print("Position #", position_id, " opened for Session ", session_index + 1);
         if(is_buy_trade) {
            stats[session_index].buy_orders_opened++;
            sessions[session_index].buy_position_id = position_id;
            if(sessions[session_index].sell_order_ticket > 0 && trade.OrderDelete(sessions[session_index].sell_order_ticket)) {
               Print("Cancelled opposing Sell Stop #", sessions[session_index].sell_order_ticket);
               sessions[session_index].sell_order_ticket = 0;
            }
         } else {
            stats[session_index].sell_orders_opened++;
            sessions[session_index].sell_position_id = position_id;
            if(sessions[session_index].buy_order_ticket > 0 && trade.OrderDelete(sessions[session_index].buy_order_ticket)) {
               Print("Cancelled opposing Buy Stop #", sessions[session_index].buy_order_ticket);
               sessions[session_index].buy_order_ticket = 0;
            }
         }
         // NEW: Delete entry lines after a trade is opened
         ObjectDelete(0, sessions[session_index].buy_entry_line_name);
         ObjectDelete(0, sessions[session_index].sell_entry_line_name);
      }
   }

   // --- B: Position was just CLOSED ---
   if(deal_entry == DEAL_ENTRY_OUT || deal_entry == DEAL_ENTRY_INOUT)
   {
      int session_index = -1; bool is_buy_trade = false;

      // NEW ROBUST LOGIC: Trace back from position to original order comment
      if(HistorySelectByPosition(position_id))
      {
         ulong first_deal_ticket = HistoryDealGetTicket(0);
         if(HistoryDealSelect(first_deal_ticket))
         {
            ulong order_ticket = HistoryDealGetInteger(first_deal_ticket, DEAL_ORDER);
            if(HistoryOrderSelect(order_ticket))
            {
               string order_comment = HistoryOrderGetString(order_ticket, ORDER_COMMENT);
               for(int i=0; i<5; i++)
               {
                  if(StringFind(order_comment, "_S" + IntegerToString(i + 1) + "_BUY") >= 0) { session_index = i; is_buy_trade = true; break; }
                  if(StringFind(order_comment, "_S" + IntegerToString(i + 1) + "_SELL") >= 0) { session_index = i; is_buy_trade = false; break; }
               }
            }
         }
      }

      if(session_index != -1) {
         Print("Position #", position_id, " closed for Session ", session_index + 1, ". Updating stats.");
         long deal_reason = HistoryDealGetInteger(deal_ticket, DEAL_REASON);
         double total_profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) + HistoryDealGetDouble(deal_ticket, DEAL_SWAP) + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
         if(is_buy_trade) {
            stats[session_index].buy_total_profit += total_profit;
            if(deal_reason == DEAL_REASON_TP) stats[session_index].buy_orders_tp++;
            if(deal_reason == DEAL_REASON_SL) stats[session_index].buy_orders_sl++;
         } else {
            stats[session_index].sell_total_profit += total_profit;
            if(deal_reason == DEAL_REASON_TP) stats[session_index].sell_orders_tp++;
            if(deal_reason == DEAL_REASON_SL) stats[session_index].sell_orders_sl++;
         }
      }
   }
}

void InvalidatePreviousOpportunities(int current_session_index)
{
    Print("Invalidating opportunities from sessions before #", current_session_index + 1);
    for(int i = 0; i < 5; i++)
    {
        // Invalidate only previous sessions, not the current one
        if(i == current_session_index) continue;

        // Invalidate pending orders
        if(sessions[i].buy_order_ticket > 0)
        {
            if(trade.OrderDelete(sessions[i].buy_order_ticket))
            {
                Print("Successfully cancelled previous Buy Stop order #", sessions[i].buy_order_ticket, " from session ", sessions[i].name);
            }
            sessions[i].buy_order_ticket = 0;
            sessions[i].buy_trade_placed = false; // Reset flag
        }
        if(sessions[i].sell_order_ticket > 0)
        {
            if(trade.OrderDelete(sessions[i].sell_order_ticket))
            {
                Print("Successfully cancelled previous Sell Stop order #", sessions[i].sell_order_ticket, " from session ", sessions[i].name);
            }
            sessions[i].sell_order_ticket = 0;
            sessions[i].sell_trade_placed = false; // Reset flag
        }

        // Invalidate confirmation opportunities by marking them as "placed"
        if(sessions[i].candles_processed >= sessions[i].candle_count && !sessions[i].buy_trade_placed && !sessions[i].sell_trade_placed)
        {
            Print("Invalidating confirmation opportunity for session ", sessions[i].name);
            sessions[i].buy_trade_placed = true;
            sessions[i].sell_trade_placed = true;

            // Also delete the visual entry lines
            ObjectDelete(0, sessions[i].buy_entry_line_name);
            ObjectDelete(0, sessions[i].sell_entry_line_name);
        }
    }
}

void CheckForConfirmationEntry()
{
    // NEW: Quick exit if trading is disabled for the day
    if(!IsTradingDayAllowed()) return;

    // Get the close price of the last completed bar on the CONFIRMATION timeframe
    double last_close = iClose(_Symbol, ConfirmationCandle, 1);
    if(last_close <= 0) return; // Safety check for valid price data

    // Iterate through all sessions
    for(int i = 0; i < 5; i++)
    {
        // Check only enabled sessions where the range has been defined but no trade has been placed yet
        if(sessions[i].enabled && sessions[i].candles_processed >= sessions[i].candle_count && !sessions[i].buy_trade_placed && !sessions[i].sell_trade_placed)
        {
            // --- DIAGNOSTIC LOGGING ---
            // Print("Checking Confirmation: Session ", sessions[i].name,
            //       ". Last Close (", EnumToString(ConfirmationCandle),"): ", DoubleToString(last_close, _Digits),
            //       ". Buy Entry: ", DoubleToString(sessions[i].buy_entry, _Digits),
            //       ". Sell Entry: ", DoubleToString(sessions[i].sell_entry, _Digits));
            // --- END DIAGNOSTIC LOGGING ---

            // Check for BUY confirmation
            if(EnableBuyTrading && last_close > sessions[i].buy_entry)
            {
                Print("BUY confirmation found for session ", sessions[i].name);
                ExecuteMarketBuy(i);
            }
            // Check for SELL confirmation
            else if(EnableSellTrading && last_close < sessions[i].sell_entry)
            {
                Print("SELL confirmation found for session ", sessions[i].name);
                ExecuteMarketSell(i);
            }
        }
    }
}

void ExecuteMarketBuy(int session_index)
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double take_profit = NormalizeDouble(sessions[session_index].buy_take_profit, _Digits);
    double stop_loss = NormalizeDouble(sessions[session_index].buy_stop_loss, _Digits);

    double volume = CalculateVolume(price, stop_loss);
    if(volume <= 0)
    {
        Print("Volume calculation failed for Market Buy, Session ", session_index + 1);
        return;
    }

    string comment = TradeComment + "_S" + IntegerToString(session_index + 1) + "_BUY_Confirm";
    if(trade.Buy(volume, _Symbol, price, stop_loss, take_profit, comment))
    {
        Print("Market Buy EXECUTED for Session ", session_index + 1, " | Vol: ", volume, " | Ticket: ", trade.ResultOrder());
        // Mark both as placed to prevent opposite trade
        sessions[session_index].buy_trade_placed = true;
        sessions[session_index].sell_trade_placed = true;
    }
}

void ExecuteMarketSell(int session_index)
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double take_profit = NormalizeDouble(sessions[session_index].sell_take_profit, _Digits);
    double stop_loss = NormalizeDouble(sessions[session_index].sell_stop_loss, _Digits);

    double volume = CalculateVolume(price, stop_loss);
    if(volume <= 0)
    {
        Print("Volume calculation failed for Market Sell, Session ", session_index + 1);
        return;
    }

    string comment = TradeComment + "_S" + IntegerToString(session_index + 1) + "_SELL_Confirm";
    if(trade.Sell(volume, _Symbol, price, stop_loss, take_profit, comment))
    {
        Print("Market Sell EXECUTED for Session ", session_index + 1, " | Vol: ", volume, " | Ticket: ", trade.ResultOrder());
        // Mark both as placed to prevent opposite trade
        sessions[session_index].buy_trade_placed = true;
        sessions[session_index].sell_trade_placed = true;
    }
}


//==================================================================
//== VISUAL & DRAWING FUNCTIONS
//==================================================================

void DrawHighLowLines(int session_index)
{
   if(sessions[session_index].session_high <= 0) return;

   // --- Clean up previous objects for this session ---
   ObjectDelete(0, sessions[session_index].high_line_name);
   ObjectDelete(0, sessions[session_index].low_line_name);
   ObjectDelete(0, sessions[session_index].high_line_name + "_Label");
   ObjectDelete(0, sessions[session_index].low_line_name + "_Label");
   ObjectDelete(0, sessions[session_index].buy_entry_line_name);
   ObjectDelete(0, sessions[session_index].sell_entry_line_name);

   // --- Draw Initial Range Lines (Solid) ---
   datetime range_start_time = sessions[session_index].session_start_dt;
   datetime range_end_time = range_start_time + (8 * 3600); // Fixed 8-hour duration

   if(ObjectCreate(0, sessions[session_index].high_line_name, OBJ_TREND, 0, range_start_time, sessions[session_index].session_high, range_end_time, sessions[session_index].session_high))
   {
      ObjectSetInteger(0, sessions[session_index].high_line_name, OBJPROP_COLOR, sessions[session_index].candle_color);
      ObjectSetInteger(0, sessions[session_index].high_line_name, OBJPROP_STYLE, STYLE_SOLID); // Solid for range
      ObjectSetInteger(0, sessions[session_index].high_line_name, OBJPROP_WIDTH, LineWidth);
   }
   if(ObjectCreate(0, sessions[session_index].low_line_name, OBJ_TREND, 0, range_start_time, sessions[session_index].session_low, range_end_time, sessions[session_index].session_low))
   {
      ObjectSetInteger(0, sessions[session_index].low_line_name, OBJPROP_COLOR, sessions[session_index].candle_color);
      ObjectSetInteger(0, sessions[session_index].low_line_name, OBJPROP_STYLE, STYLE_SOLID); // Solid for range
      ObjectSetInteger(0, sessions[session_index].low_line_name, OBJPROP_WIDTH, LineWidth);
   }
   if(ShowLabels)
   {
      // High Label
      string high_label_name = sessions[session_index].high_line_name + "_Label";
      string high_label_text = " " + sessions[session_index].name + " High (" + DoubleToString(sessions[session_index].session_high, _Digits) + ")";
      if(ObjectCreate(0, high_label_name, OBJ_TEXT, 0, range_start_time, sessions[session_index].session_high))
      {
         ObjectSetString(0, high_label_name, OBJPROP_TEXT, high_label_text);
         ObjectSetInteger(0, high_label_name, OBJPROP_COLOR, sessions[session_index].candle_color);
         ObjectSetInteger(0, high_label_name, OBJPROP_FONTSIZE, 8);
         ObjectSetString(0, high_label_name, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, high_label_name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
         ObjectSetInteger(0, high_label_name, OBJPROP_BACK, true);
      }

      // Low Label
      string low_label_name = sessions[session_index].low_line_name + "_Label";
      string low_label_text = " " + sessions[session_index].name + " Low (" + DoubleToString(sessions[session_index].session_low, _Digits) + ")";
      if(ObjectCreate(0, low_label_name, OBJ_TEXT, 0, range_start_time, sessions[session_index].session_low))
      {
         ObjectSetString(0, low_label_name, OBJPROP_TEXT, low_label_text);
         ObjectSetInteger(0, low_label_name, OBJPROP_COLOR, sessions[session_index].candle_color);
         ObjectSetInteger(0, low_label_name, OBJPROP_FONTSIZE, 8);
         ObjectSetString(0, low_label_name, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, low_label_name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
         ObjectSetInteger(0, low_label_name, OBJPROP_BACK, true);
      }
   }

   // --- If Confirmation Mode, Draw Entry Lines (Dotted, Dynamic Length) ---
   if(WaitForConfirmation)
   {
      datetime entry_line_start_time = sessions[session_index].session_start_dt + (sessions[session_index].candle_count * PeriodSeconds(sessions[session_index].timeframe));
      datetime entry_line_end_time = 0;

      int next_session_index = FindNextActiveSession(session_index);
      if(next_session_index != -1)
      {
         datetime next_session_start_today = GetTimeFromString(sessions[next_session_index].start_time);
         if(next_session_start_today < sessions[session_index].session_start_dt)
         {
            next_session_start_today += 24 * 3600; // Add a day if it wraps around
         }
         entry_line_end_time = next_session_start_today + (sessions[next_session_index].candle_count * PeriodSeconds(sessions[next_session_index].timeframe));
      }
      else
      {
         entry_line_end_time = entry_line_start_time + (8 * 3600); // Default duration if no next session
      }

      if(ObjectCreate(0, sessions[session_index].buy_entry_line_name, OBJ_TREND, 0, entry_line_start_time, sessions[session_index].buy_entry, entry_line_end_time, sessions[session_index].buy_entry))
      {
         ObjectSetInteger(0, sessions[session_index].buy_entry_line_name, OBJPROP_COLOR, sessions[session_index].candle_color);
         ObjectSetInteger(0, sessions[session_index].buy_entry_line_name, OBJPROP_STYLE, STYLE_DOT); // Dotted for entry
         ObjectSetInteger(0, sessions[session_index].buy_entry_line_name, OBJPROP_WIDTH, LineWidth);
      }
      if(ObjectCreate(0, sessions[session_index].sell_entry_line_name, OBJ_TREND, 0, entry_line_start_time, sessions[session_index].sell_entry, entry_line_end_time, sessions[session_index].sell_entry))
      {
         ObjectSetInteger(0, sessions[session_index].sell_entry_line_name, OBJPROP_COLOR, sessions[session_index].candle_color);
         ObjectSetInteger(0, sessions[session_index].sell_entry_line_name, OBJPROP_STYLE, STYLE_DOT); // Dotted for entry
         ObjectSetInteger(0, sessions[session_index].sell_entry_line_name, OBJPROP_WIDTH, LineWidth);
      }
   }

   ChartRedraw(0);
}
