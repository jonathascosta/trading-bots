//+------------------------------------------------------------------+
//|  AurumLeg.mq5                                                          |
//|  Copyright (c) 2026, Jonathas Costa                              |
//|  github.com/jonathascosta/trading-bots                           |
//|                                                                  |
//|  MIT License - free to use and modify, keeping this              |
//|  header and copyright notice in all copies.                      |
//+------------------------------------------------------------------+
#property copyright "Jonathas Costa"
#property link      "https://github.com/jonathascosta/trading-bots"
#property version   "1.02"
#property strict

#include <Trade\Trade.mqh>

#define SWING_IGNORED  0
#define SWING_APPENDED 1
#define SWING_REPLACED 2

input double InpLots          = 0.01;             // Fixed lot (used when risk % = 0)
input double InpRiskPercent   = 1.5;              // Risk % of equity per trade (historical maxDD ~45-50%)
input double InpRetrMin       = 38.0;             // Min retracement %
input double InpRetrMax       = 62.0;             // Max retracement %
input double InpTPMult        = 1.5;              // TP multiple of medLeg
input double InpSLMult        = 1.5;              // SL multiple of medLeg
input int    InpLegsWindow    = 20;               // Legs in rolling median
input double InpMinMedLeg     = 8.0;              // Min medLeg in $ to trade
input string InpBlockedHours  = "0,13,14,15,16";  // Blocked server hours
input int    InpMaxSpreadPts  = 35;               // Max spread (points) to enter
input int    InpMaxPositions  = 5;                // Max open positions (0 = unlimited)
input bool   InpOnePerPivot   = true;             // Skip re-signals when a pivot deepens
input int    InpWarmupBars    = 1000;             // History bars to rebuild zigzag state
input long   InpMagic         = 20260717;         // Magic number

CTrade   g_trade;
bool     g_blockedHour[24];

double   g_pivPrice[];
bool     g_pivIsMax[];
int      g_pivCount = 0;

double   g_legs[];
int      g_legCount = 0;

datetime g_lastBar = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);

   ArrayInitialize(g_blockedHour, false);
   string parts[];
   int n = StringSplit(InpBlockedHours, ',', parts);
   for(int i = 0; i < n; i++)
     {
      int hh = (int)StringToInteger(parts[i]);
      if(hh >= 0 && hh < 24)
         g_blockedHour[hh] = true;
     }

   // Rebuild zigzag state from history so medLeg is ready on first tick.
   // Oldest center first; center shift s is confirmed by bar s-1.
   for(int s = InpWarmupBars; s >= 2; s--)
      ProcessConfirmedCenter(s, false);
   g_lastBar = iTime(_Symbol, _Period, 0);

   PrintFormat("AurumLeg: warmup done, pivots=%d legs=%d medLeg=%.2f",
               g_pivCount, g_legCount, MedLeg());
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime bar = iTime(_Symbol, _Period, 0);
   if(bar == g_lastBar)
      return;
   g_lastBar = bar;

   // Bar 1 just closed and confirms the fractal centered on bar 2
   ProcessConfirmedCenter(2, true);
  }
//+------------------------------------------------------------------+
//| Evaluate the 3-bar swing centered at `center` and update zigzag. |
//| When `allowTrade` a qualifying new/updated pivot fires an entry. |
//+------------------------------------------------------------------+
void ProcessConfirmedCenter(const int center, const bool allowTrade)
  {
   double hC = iHigh(_Symbol, _Period, center);
   double hL = iHigh(_Symbol, _Period, center + 1);
   double hR = iHigh(_Symbol, _Period, center - 1);
   double lC = iLow(_Symbol, _Period, center);
   double lL = iLow(_Symbol, _Period, center + 1);
   double lR = iLow(_Symbol, _Period, center - 1);

   bool isH = (hC >= hL && hC >= hR);
   bool isL = (lC <= lL && lC <= lR);
   if(!isH && !isL)
      return;

   double price[2];
   bool   isMax[2];
   int    cand = 0;
   if(isH && isL)
     {
      // Insert in the order that keeps min/max alternation
      bool lastWasMax = (g_pivCount > 0 && g_pivIsMax[g_pivCount - 1]);
      if(lastWasMax)
        { price[0] = lC; isMax[0] = false; price[1] = hC; isMax[1] = true; }
      else
        { price[0] = hC; isMax[0] = true;  price[1] = lC; isMax[1] = false; }
      cand = 2;
     }
   else
     {
      price[0] = isH ? hC : lC;
      isMax[0] = isH;
      cand = 1;
     }

   for(int i = 0; i < cand; i++)
     {
      int res = RegisterSwing(price[i], isMax[i]);
      if(res != SWING_IGNORED)
         OnPivotEvent(allowTrade, res == SWING_REPLACED);
     }
  }
//+------------------------------------------------------------------+
//| Keep strict alternation; same type keeps the more extreme value. |
//+------------------------------------------------------------------+
int RegisterSwing(const double price, const bool isMax)
  {
   if(g_pivCount > 0 && g_pivIsMax[g_pivCount - 1] == isMax)
     {
      bool moreExtreme = isMax ? (price >= g_pivPrice[g_pivCount - 1])
                               : (price <= g_pivPrice[g_pivCount - 1]);
      if(!moreExtreme)
         return(SWING_IGNORED);
      g_pivPrice[g_pivCount - 1] = price;
      return(SWING_REPLACED);
     }
   if(g_pivCount >= ArraySize(g_pivPrice))
     {
      ArrayResize(g_pivPrice, g_pivCount + 256);
      ArrayResize(g_pivIsMax, g_pivCount + 256);
     }
   g_pivPrice[g_pivCount] = price;
   g_pivIsMax[g_pivCount] = isMax;
   g_pivCount++;
   return(SWING_APPENDED);
  }
//+------------------------------------------------------------------+
void OnPivotEvent(const bool allowTrade, const bool isReplacement)
  {
   if(g_pivCount < 2)
      return;

   // Record leg size on every pivot event (mirrors backtest behavior)
   if(g_pivCount >= 3)
     {
      if(g_legCount >= ArraySize(g_legs))
         ArrayResize(g_legs, g_legCount + 512);
      g_legs[g_legCount++] = MathAbs(g_pivPrice[g_pivCount - 1] - g_pivPrice[g_pivCount - 2]);
     }

   if(!allowTrade || g_pivCount < 3 || g_legCount < InpLegsWindow)
      return;

   // Deeper extreme on an already-signaled pivot: leg recorded above, no re-entry
   if(InpOnePerPivot && isReplacement)
      return;

   double pL = g_pivPrice[g_pivCount - 3];
   double pM = g_pivPrice[g_pivCount - 2];
   double pC = g_pivPrice[g_pivCount - 1];
   double range = MathAbs(pM - pL);
   if(range <= 0.0)
      return;
   double retr = MathAbs(pC - pM) / range * 100.0;
   if(retr < InpRetrMin || retr >= InpRetrMax)
      return;

   double medLeg = MedLeg();
   if(medLeg < InpMinMedLeg)
      return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(g_blockedHour[dt.hour])
      return;

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPts)
      return;

   if(InpMaxPositions > 0 && CountOwnPositions() >= InpMaxPositions)
      return;

   bool isLong = !g_pivIsMax[g_pivCount - 1];  // low pivot -> continuation up
   double lots = CalcLots(InpSLMult * medLeg);
   if(lots <= 0.0)
      return;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(isLong)
     {
      double tp = NormalizeDouble(ask + InpTPMult * medLeg, _Digits);
      double sl = NormalizeDouble(ask - InpSLMult * medLeg, _Digits);
      g_trade.Buy(lots, _Symbol, 0.0, sl, tp, "AurumLeg");
     }
   else
     {
      double tp = NormalizeDouble(bid - InpTPMult * medLeg, _Digits);
      double sl = NormalizeDouble(bid + InpSLMult * medLeg, _Digits);
      g_trade.Sell(lots, _Symbol, 0.0, sl, tp, "AurumLeg");
     }
  }
//+------------------------------------------------------------------+
//| Volume for InpRiskPercent of equity at the given SL distance.    |
//| Falls back to InpLots when risk sizing is disabled or fails.     |
//+------------------------------------------------------------------+
double CalcLots(const double slDistance)
  {
   if(InpRiskPercent <= 0.0)
      return(InpLots);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || slDistance <= 0.0)
      return(InpLots);
   double lossPerLot = slDistance / tickSize * tickValue;
   double riskMoney  = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double lots = riskMoney / lossPerLot;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step > 0.0)
      lots = MathFloor(lots / step) * step;
   if(lots < vmin)
      return(0.0);   // risk budget too small for min volume: skip, never oversize
   return(MathMin(lots, vmax));
  }
//+------------------------------------------------------------------+
//| Median of the last InpLegsWindow legs (mean of middle pair)      |
//+------------------------------------------------------------------+
double MedLeg()
  {
   int w = MathMin(InpLegsWindow, g_legCount);
   if(w == 0)
      return(0.0);
   double tmp[];
   ArrayResize(tmp, w);
   for(int i = 0; i < w; i++)
      tmp[i] = g_legs[g_legCount - w + i];
   ArraySort(tmp);
   if(w % 2 == 1)
      return(tmp[w / 2]);
   return(0.5 * (tmp[w / 2 - 1] + tmp[w / 2]));
  }
//+------------------------------------------------------------------+
int CountOwnPositions()
  {
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagic
         && PositionGetString(POSITION_SYMBOL) == _Symbol)
         cnt++;
     }
   return(cnt);
  }
//+------------------------------------------------------------------+
