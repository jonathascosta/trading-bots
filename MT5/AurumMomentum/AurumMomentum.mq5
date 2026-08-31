//+------------------------------------------------------------------+
//|  AurumMomentum.mq5                                                          |
//|  Copyright (c) 2026, Jonathas Costa                              |
//|  github.com/jonathascosta/trading-bots                           |
//|                                                                  |
//|  MIT License - free to use and modify, keeping this              |
//|  header and copyright notice in all copies.                      |
//+------------------------------------------------------------------+
#property copyright "Jonathas Costa"
#property link      "https://github.com/jonathascosta/trading-bots"
#property version   "1.30"
#property strict

#include <Trade/Trade.mqh>

input double InpLots        = 0.01;     // Lot size per operation
input int    InpSLPoints    = 0;        // Stop loss in points (0 = none)
input int    InpTPPoints    = 0;        // Take profit in points (0 = none)
input int    InpExitMode    = 1;        // Exit: 0 = basket target, 1 = time exit
input int    InpHoldBars    = 1;        // Mode 1: close position after this many candles
input double InpMinBodyATR  = 0.0;      // Min candle body as multiple of ATR (0 = off)
input int    InpATRPeriod   = 14;       // ATR period for the body filter
input double InpProfitPerOp = 1.00;     // Mode 0: basket target per operation, account currency (0 = off)
input long   InpMagic       = 20260706; // Magic number

CTrade   g_trade;
datetime g_lastBarTime = 0;
int      g_atrHandle   = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   if(InpMinBodyATR > 0.0)
   {
      g_atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
      if(g_atrHandle == INVALID_HANDLE)
      {
         Print("AurumMomentum: failed to create ATR indicator");
         return INIT_FAILED;
      }
   }
   // Skip the bar already in progress at attach time
   g_lastBarTime = iTime(_Symbol, _Period, 0);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(InpExitMode == 0)
      CheckBasketTarget();

   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == g_lastBarTime)
      return;
   g_lastBarTime = barTime;

   // Mode 1: close positions that have been open for InpHoldBars candles
   if(InpExitMode == 1)
      CloseExpiredPositions();

   double open  = iOpen(_Symbol, _Period, 1);
   double close = iClose(_Symbol, _Period, 1);
   if(close == open)
      return; // doji has no direction

   // Momentum filter: only trade candles with a body of at least
   // InpMinBodyATR * ATR of the closed bar
   if(InpMinBodyATR > 0.0)
   {
      double atr[1];
      if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) != 1)
         return;
      if(MathAbs(close - open) < InpMinBodyATR * atr[0])
         return;
   }

   bool   isBuy  = (close > open);
   double price  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                         : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double sl = 0.0, tp = 0.0;
   if(InpSLPoints > 0)
      sl = NormalizeDouble(isBuy ? price - InpSLPoints * point
                                 : price + InpSLPoints * point, digits);
   if(InpTPPoints > 0)
      tp = NormalizeDouble(isBuy ? price + InpTPPoints * point
                                 : price - InpTPPoints * point, digits);

   double lots = NormalizeLots(InpLots);
   bool ok = isBuy ? g_trade.Buy(lots, _Symbol, 0.0, sl, tp)
                   : g_trade.Sell(lots, _Symbol, 0.0, sl, tp);
   if(!ok)
      PrintFormat("AurumMomentum: order failed, retcode=%d (%s)",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Close all EA positions once total floating profit (incl. swap)   |
//| reaches max(buys, sells) * InpProfitPerOp                        |
//+------------------------------------------------------------------+
void CheckBasketTarget()
{
   if(InpProfitPerOp <= 0.0)
      return;

   int    buys = 0, sells = 0;
   double profit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i); // also selects the position
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         buys++;
      else
         sells++;
      profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }

   int dominant = MathMax(buys, sells);
   if(dominant == 0)
      return;

   double target = dominant * InpProfitPerOp;
   if(profit < target)
      return;

   PrintFormat("AurumMomentum: basket target hit (profit=%.2f >= target=%.2f, %d buys / %d sells), closing all",
               profit, target, buys, sells);
   CloseAllPositions();
}

//+------------------------------------------------------------------+
//| Close EA positions opened InpHoldBars or more candles ago        |
//+------------------------------------------------------------------+
void CloseExpiredPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(iBarShift(_Symbol, _Period, posTime) < InpHoldBars)
         continue;
      if(!g_trade.PositionClose(ticket))
         PrintFormat("AurumMomentum: failed to close #%I64u, retcode=%d (%s)",
                     ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Close every position of this EA on this symbol                   |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(!g_trade.PositionClose(ticket))
         PrintFormat("AurumMomentum: failed to close #%I64u, retcode=%d (%s)",
                     ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Clamp requested volume to broker min/max and round to lot step   |
//+------------------------------------------------------------------+
double NormalizeLots(double lots)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double result = MathMax(minLot, MathMin(maxLot, lots));
   if(lotStep > 0.0)
      result = MathRound(result / lotStep) * lotStep;
   if(result != lots)
      PrintFormat("AurumMomentum: lot adjusted from %.2f to %.2f (broker limits)",
                  lots, result);
   return result;
}
//+------------------------------------------------------------------+
