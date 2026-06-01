//+------------------------------------------------------------------+
//|  EveryCandle.mq5                                                 |
//|  Copyright (c) 2025-2026, Jonathas Costa                         |
//|  github.com/jonathas/trading-bots                                |
//|                                                                  |
//|  Licenca MIT - uso e modificacao livres, mantendo este           |
//|  cabecalho e aviso de copyright em todas as copias.              |
//+------------------------------------------------------------------+
#property copyright "Jonathas Costa"
#property link      "https://github.com/jonathas/trading-bots"

#include <Trade/Trade.mqh>

CTrade trade;

//==================================================
// Lista de timeframes suportados
//==================================================
ENUM_TIMEFRAMES tfList[] =
{
   PERIOD_M1, PERIOD_M2, PERIOD_M3, PERIOD_M4, PERIOD_M5,
   PERIOD_M6, PERIOD_M10, PERIOD_M12, PERIOD_M15, PERIOD_M20,
   PERIOD_M30, PERIOD_H1, PERIOD_H2, PERIOD_H3, PERIOD_H4,
   PERIOD_H6, PERIOD_H8, PERIOD_H12, PERIOD_D1, PERIOD_W1, PERIOD_MN1
};

datetime lastBarTimeByTF[21];

//==================================================
int TfIndex(int tfSeconds)
{
   for(int i = 0; i < ArraySize(tfList); i++)
      if(PeriodSeconds(tfList[i]) == tfSeconds)
         return i;

   return -1;
}

//==================================================
// Detecta nova vela REAL do timeframe atual
//==================================================
bool IsNewBarCurrentTF()
{
   int idx = TfIndex(PeriodSeconds(_Period));
   if(idx < 0)
      return false;

   datetime current = iTime(_Symbol, _Period, 0);

   // Primeiro contato com este TF
   if(lastBarTimeByTF[idx] == 0)
   {
      lastBarTimeByTF[idx] = current;
      return false;
   }

   if(lastBarTimeByTF[idx] == current)
      return false;

   lastBarTimeByTF[idx] = current;
   return true;
}

//==================================================
bool HasOpenPositionForCurrentTF()
{
   long magic = PeriodSeconds(_Period);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      if(PositionGetInteger(POSITION_MAGIC) == magic)
         return true;
   }
   return false;
}

//==================================================
// Fecha trades quando a vela do TIMEFRAME DE ORIGEM
// do trade fecha em lucro, independente do TF atual
//==================================================
void ManageAllOpenPositionsByTheirTF()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long magic = PositionGetInteger(POSITION_MAGIC); // segundos do TF
      int idx = TfIndex((int)magic);
      if(idx < 0) continue;

      ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)tfList[idx];
      datetime currentBarTime = iTime(_Symbol, tf, 0);

      // Primeiro contato com esse TF
      if(lastBarTimeByTF[idx] == 0)
      {
         lastBarTimeByTF[idx] = currentBarTime;
         continue;
      }

      // Ainda na mesma vela
      if(lastBarTimeByTF[idx] == currentBarTime)
         continue;

      // Nova vela do TF do trade iniciou
      lastBarTimeByTF[idx] = currentBarTime;

      double profit = PositionGetDouble(POSITION_PROFIT);
      if(profit > 0)
      {
         trade.PositionClose(ticket);
      }
   }
}

//==================================================
// Abre trade baseado na vela anterior (V0)
//==================================================
void OpenTradeBasedOnPreviousCandle()
{
   double open0  = iOpen(_Symbol, _Period, 1);
   double close0 = iClose(_Symbol, _Period, 1);
   double high0  = iHigh(_Symbol, _Period, 1);
   double low0   = iLow(_Symbol, _Period, 1);

   trade.SetExpertMagicNumber(PeriodSeconds(_Period));

   double lot = 0.1;

   if(close0 > open0)
   {
      trade.Buy(lot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), low0, 0);
   }
   else
   {
      trade.Sell(lot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), high0, 0);
   }
}

//==================================================
int OnInit()
{
   ArrayInitialize(lastBarTimeByTF, 0);
   return INIT_SUCCEEDED;
}

//==================================================
void OnTick()
{
   // 1) Gerencia fechamento de trades por TF de origem
   ManageAllOpenPositionsByTheirTF();

   // 2) Só abre trade no início real da vela do TF atual
   if(!IsNewBarCurrentTF())
      return;

   if(HasOpenPositionForCurrentTF())
      return;

   OpenTradeBasedOnPreviousCandle();
}
