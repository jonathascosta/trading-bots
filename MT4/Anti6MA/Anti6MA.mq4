//+------------------------------------------------------------------+
//|  Anti6MA.mq4                                                     |
//|  Copyright (c) 2025-2026, Jonathas Costa                         |
//|  github.com/jonathas/trading-bots                                |
//|                                                                  |
//|  MIT License - free to use and modify, keeping this              |
//|  header and copyright notice in all copies.                      |
//+------------------------------------------------------------------+
#property copyright "Jonathas Costa"
#property link      "https://github.com/jonathas/trading-bots"

#property strict
#property version "3.2"

extern double    PipValue        = 0.1;    // WARNING: Change PIP value
extern double    ReentryPips     = 87.0;   // Minimum pips for Martingale
extern double    ExitProfitPips  = 38.0;   // Minimum profit in pips to close
extern int       MagicNumber     = 12345;
extern int       Slippage        = 3;
extern int       MA_Period       = 6;

double   lastSellEntryPrice = 0;
double   lastSellLot        = 0;
double   lastBuyEntryPrice  = 0;
double   lastBuyLot         = 0;
datetime lastOrderTime      = 0;

int CountOrders(int opType)
{
   int count = 0;
   for (int i = 0; i < OrdersTotal(); i++)
   {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderType() == opType)
            count++;
      }
   }
   return count;
}

double AggregateProfitPips()
{
   double totalPips = 0;
   for (int i = 0; i < OrdersTotal(); i++)
   {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
         {
            double lot = OrderLots();
            if (OrderType() == OP_SELL)
            {
               totalPips += ((OrderOpenPrice() - Bid) / PipValue) * lot;
            }
            else if (OrderType() == OP_BUY)
            {
               totalPips += ((Ask - OrderOpenPrice()) / PipValue) * lot;
            }
         }
      }
   }
   return totalPips;
}

bool OpenSellOrder(double lot)
{
   double price = Bid;
   int ticket = OrderSend(Symbol(), OP_SELL, lot, price, Slippage, 0, 0, "Sell Order", MagicNumber, 0, Red);
   if(ticket < 0)
   {
      Print("Error opening SELL order: ", GetLastError());
      return false;
   }
   lastOrderTime = TimeCurrent();
   return true;
}

bool OpenBuyOrder(double lot)
{
   double price = Ask;
   int ticket = OrderSend(Symbol(), OP_BUY, lot, price, Slippage, 0, 0, "Buy Order", MagicNumber, 0, Blue);
   if(ticket < 0)
   {
      Print("Error opening BUY order: ", GetLastError());
      return false;
   }
   lastOrderTime = TimeCurrent();
   return true;
}

void CloseAllOrders()
{
   for (int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
         {
            bool closed = false;
            if(OrderType() == OP_BUY)
               closed = OrderClose(OrderTicket(), OrderLots(), Bid, Slippage, clrYellow);
            else if(OrderType() == OP_SELL)
               closed = OrderClose(OrderTicket(), OrderLots(), Ask, Slippage, clrYellow);
            if(!closed)
               Print("Error closing order ", OrderTicket(), ": ", GetLastError());
         }
      }
   }

   lastSellEntryPrice = 0;
   lastSellLot = 0;
   lastBuyEntryPrice = 0;
   lastBuyLot = 0;
}

void RestoreTradeVars()
{
   datetime latestBuyTime = 0;
   datetime latestSellTime = 0;
   int buyCount = 0;
   int sellCount = 0;

   for (int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
         {
            if(OrderType() == OP_BUY)
            {
               buyCount++;
               if(OrderOpenTime() > latestBuyTime)
               {
                  latestBuyTime = OrderOpenTime();
                  lastBuyEntryPrice = OrderOpenPrice();
                  lastBuyLot = OrderLots();
               }
            }
            else if(OrderType() == OP_SELL)
            {
               sellCount++;
               if(OrderOpenTime() > latestSellTime)
               {
                  latestSellTime = OrderOpenTime();
                  lastSellEntryPrice = OrderOpenPrice();
                  lastSellLot = OrderLots();
               }
            }
         }
      }
   }

   Print("Debug RestoreTradeVars: ", buyCount, " BUY orders found; Last BUY entry price = ",
         DoubleToStr(lastBuyEntryPrice, Digits), ", Last BUY lot = ", DoubleToStr(lastBuyLot, 2));

   Print("Debug RestoreTradeVars: ", sellCount, " SELL orders found; Last SELL entry price = ",
         DoubleToStr(lastSellEntryPrice, Digits), ", Last SELL lot = ", DoubleToStr(lastSellLot, 2));
}

int init()
{
   if(ObjectFind("ResetButton") < 0)
   {
      ObjectCreate("ResetButton", OBJ_BUTTON, 0, 0, 0);
      ObjectSet("ResetButton", OBJPROP_CORNER, 0);
      ObjectSet("ResetButton", OBJPROP_XDISTANCE, 10);
      ObjectSet("ResetButton", OBJPROP_YDISTANCE, 80);  // Posicionado logo abaixo do Comment
      ObjectSetText("ResetButton", "Close All Trades and Reset", 12, "Arial", clrWhite);
   }
   return(0);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == "ResetButton")
   {
      Print("Reset button clicked! Closing trades and resetting variables.");
      CloseAllOrders();
   }
}

int deinit()
{
   ObjectDelete("ResetButton");
   return(0);
}

int start()
{
   RestoreTradeVars();

   CheckAndCloseIfBalancedAndProfit();

   double minLot   = MarketInfo(Symbol(), MODE_MINLOT);
   double lotStep  = MarketInfo(Symbol(), MODE_LOTSTEP);

   double dynamicInitialLot = MathFloor(AccountBalance() / 100000.0) * 0.1;
   if(dynamicInitialLot < 0.1)
       dynamicInitialLot = 0.1;
   if(dynamicInitialLot < minLot)
       dynamicInitialLot = minLot;

   double ma = iMA(NULL, 0, MA_Period, 0, MODE_SMA, PRICE_CLOSE, 0);
   double maPrev = iMA(NULL, 0, MA_Period, 0, MODE_SMA, PRICE_CLOSE, 1);
   bool maRising = (ma > maPrev);
   bool maFalling = (ma < maPrev);

   if (TimeCurrent() - lastOrderTime < 1)
      return(0);

   int sellCount = CountOrders(OP_SELL);
   if(maRising)
   {
      if(sellCount == 0)
      {
         if(OpenSellOrder(dynamicInitialLot))
         {
            lastSellEntryPrice = Bid;
            lastSellLot = dynamicInitialLot;
         }
      }
      else
      {
         if(Bid >= lastSellEntryPrice + ReentryPips * PipValue)
         {
            double newLot = lastSellLot * 2;
            if(OpenSellOrder(newLot))
            {
               lastSellEntryPrice = Bid;
               lastSellLot = newLot;
            }
         }
      }
   }

   int buyCount = CountOrders(OP_BUY);
   if(maFalling)
   {
      if(buyCount == 0)
      {
         if(OpenBuyOrder(dynamicInitialLot))
         {
            lastBuyEntryPrice = Ask;
            lastBuyLot = dynamicInitialLot;
         }
      }
      else
      {
         if(Ask <= lastBuyEntryPrice - ReentryPips * PipValue)
         {
            double newLot = lastBuyLot * 2;
            if(OpenBuyOrder(newLot))
            {
               lastBuyEntryPrice = Ask;
               lastBuyLot = newLot;
            }
         }
      }
   }

   double totalProfitPips = AggregateProfitPips();
   double dynamicExitProfit = CalcDynamicExitProfitPips(lastSellLot > lastBuyLot ? lastSellLot : lastBuyLot, dynamicInitialLot, ExitProfitPips);

   if(totalProfitPips >= dynamicExitProfit)
   {
      CloseAllOrders();
   }

   if(sellCount > 0)
      DrawDynamicSellLevels();

   if(buyCount > 0)
      DrawDynamicBuyLevels();

   double progress = totalProfitPips / dynamicExitProfit;
   if(progress > 1.0) progress = 1.0;

   int progressBarLength = 20;
   int filledBars = (int)MathRound(progress * progressBarLength);
   string progressBar = "";
   for (int i = 0; i < progressBarLength; i++)
   {
      if(i < filledBars)
         progressBar += "#";
      else
         progressBar += "-";
   }

   Comment("Profit: ", DoubleToStr(totalProfitPips,2), " pips\nProgress: [", progressBar, "] ", DoubleToStr(progress * 100,0), "%");

   return(0);
}

double CalcDynamicExitProfitPips(double currentLot, double baseLot, double baseExitProfitPips)
{
   double multiplier = currentLot / baseLot;
   if(multiplier <= 8)
      return baseExitProfitPips;
   else
      return baseExitProfitPips * (8.0 / multiplier);
}

void CheckAndCloseIfBalancedAndProfit()
{
   int sellCount = CountOrders(OP_SELL);
   int buyCount = CountOrders(OP_BUY);

   if(sellCount > 0 && sellCount == buyCount)
   {
      double totalProfitPips = AggregateProfitPips();

      if(totalProfitPips > 0)
      {
         Print("Equal number of BUY and SELL orders with profit (", DoubleToStr(totalProfitPips,2), " pips). Closing all trades.");
         CloseAllOrders();
      }
   }
}

double SimulatedSellEquity(double S)
{
   double eq = AccountBalance();

   for(int i = 0; i < OrdersTotal(); i++)
   {
       if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
       {
           if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderType() == OP_SELL)
           {
               eq += ((OrderOpenPrice() - S) / PipValue) * OrderLots();
           }
           if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderType() == OP_BUY)
           {
               eq += ((S - OrderOpenPrice()) / PipValue) * OrderLots();
           }
       }
   }

   double simPrice = lastSellEntryPrice;
   double simLot   = lastSellLot;

   while(S >= simPrice + ReentryPips * PipValue)
   {
       simPrice += ReentryPips * PipValue;
       simLot   *= 2;

       eq += ((simPrice - S) / PipValue) * simLot;
   }

   return eq;

}

double SimulatedBuyEquity(double S)
{
   double eq = AccountBalance();

   for(int i = 0; i < OrdersTotal(); i++)
   {
       if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
       {
           if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderType() == OP_SELL)
           {
               eq += ((OrderOpenPrice() - S) / PipValue) * OrderLots();
           }
           if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderType() == OP_BUY)
           {
               eq += ((S - OrderOpenPrice()) / PipValue) * OrderLots();
           }
       }
   }

   double simPrice = lastBuyEntryPrice;
   double simLot   = lastBuyLot;

   while(S <= simPrice - ReentryPips * PipValue)
   {
       simPrice -= ReentryPips * PipValue;
       simLot   *= 2;

       eq += ((S - simPrice) / PipValue) * simLot;
   }

   return eq;
}

void DrawDynamicSellLevels()
{
   if(lastSellEntryPrice <= 0)
      return;

   int maxLevels = 15;

   for(int i = 0; i < maxLevels; i++)
   {
       string objName = "SellSimLevel_" + IntegerToString(i);
       if(ObjectFind(objName) != -1)
           ObjectDelete(objName);
   }

   if(ObjectFind("SellBlowout") != -1)
       ObjectDelete("SellBlowout");

   for(int n = 0; n < maxLevels; n++)
   {
       double levelPrice = lastSellEntryPrice + n * (ReentryPips * PipValue);
       double predictedLot = lastSellLot;
       if(n > 0)
           predictedLot = lastSellLot * MathPow(2, n);

       double simEquity = SimulatedSellEquity(levelPrice);

       string objName = "SellSimLevel_" + IntegerToString(n);
       if(ObjectFind(objName) < 0)
           ObjectCreate(objName, OBJ_HLINE, 0, Time[0], levelPrice);
       else
           ObjectSet(objName, OBJPROP_PRICE, levelPrice);

       ObjectSet(objName, OBJPROP_COLOR, Orange);
       ObjectSet(objName, OBJPROP_STYLE, STYLE_DOT);
       ObjectSet(objName, OBJPROP_WIDTH, 1);

       Print("SELL Level ", n, " - Price: ", DoubleToStr(levelPrice, Digits),
             " | Predicted Lot: ", DoubleToStr(predictedLot, 2),
             " | Simulated Equity: ", DoubleToStr(simEquity,2));

       if(simEquity <= 0)
       {
           string blowName = "SellBlowout";
           if(ObjectFind(blowName) < 0)
               ObjectCreate(blowName, OBJ_HLINE, 0, Time[0], levelPrice);
           else
               ObjectSet(blowName, OBJPROP_PRICE, levelPrice);
           ObjectSet(blowName, OBJPROP_COLOR, Red);
           ObjectSet(blowName, OBJPROP_WIDTH, 3);
           ObjectSet(blowName, OBJPROP_STYLE, STYLE_SOLID);

           Print("SELL Blowout Level: Price: ", DoubleToStr(levelPrice, Digits),
                 " | Predicted Lot: ", DoubleToStr(predictedLot,2));
           break;
       }
   }
}


void DrawDynamicBuyLevels()
{
   if(lastBuyEntryPrice <= 0)
      return;

   int maxLevels = 15;

   for(int i = 0; i < maxLevels; i++)
   {
       string objName = "BuySimLevel_" + IntegerToString(i);
       if(ObjectFind(objName) != -1)
           ObjectDelete(objName);
   }

   if(ObjectFind("BuyBlowout") != -1)
       ObjectDelete("BuyBlowout");

   for(int n = 0; n < maxLevels; n++)
   {
       double levelPrice = lastBuyEntryPrice - n * (ReentryPips * PipValue);
       double predictedLot = lastBuyLot;
       if(n > 0)
           predictedLot = lastBuyLot * MathPow(2, n);

       double simEquity = SimulatedBuyEquity(levelPrice);

       string objName = "BuySimLevel_" + IntegerToString(n);
       if(ObjectFind(objName) < 0)
           ObjectCreate(objName, OBJ_HLINE, 0, Time[0], levelPrice);
       else
           ObjectSet(objName, OBJPROP_PRICE, levelPrice);

       ObjectSet(objName, OBJPROP_COLOR, Cyan);
       ObjectSet(objName, OBJPROP_STYLE, STYLE_DOT);
       ObjectSet(objName, OBJPROP_WIDTH, 1);

       Print("BUY Level ", n, " - Price: ", DoubleToStr(levelPrice, Digits),
             " | Predicted Lot: ", DoubleToStr(predictedLot, 2),
             " | Simulated Equity: ", DoubleToStr(simEquity,2));

       if(simEquity <= 0)
       {
           string blowName = "BuyBlowout";
           if(ObjectFind(blowName) < 0)
               ObjectCreate(blowName, OBJ_HLINE, 0, Time[0], levelPrice);
           else
               ObjectSet(blowName, OBJPROP_PRICE, levelPrice);
           ObjectSet(blowName, OBJPROP_COLOR, Red);
           ObjectSet(blowName, OBJPROP_WIDTH, 3);
           ObjectSet(blowName, OBJPROP_STYLE, STYLE_SOLID);

           Print("BUY Blowout Level: Price: ", DoubleToStr(levelPrice, Digits),
                 " | Predicted Lot: ", DoubleToStr(predictedLot,2));
           break;
       }
   }
}