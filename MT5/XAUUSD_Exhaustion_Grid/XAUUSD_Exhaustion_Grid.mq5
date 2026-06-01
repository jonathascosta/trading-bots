//+------------------------------------------------------------------+
//|  XAUUSD_Exhaustion_Grid.mq5                                      |
//|  Copyright (c) 2025-2026, Jonathas Costa                         |
//|  github.com/jonathas/trading-bots                                |
//|                                                                  |
//|  Licenca MIT - uso e modificacao livres, mantendo este           |
//|  cabecalho e aviso de copyright em todas as copias.              |
//+------------------------------------------------------------------+
#property copyright "Jonathas Costa"
#property link      "https://github.com/jonathas/trading-bots"

#property version   "1.70" // Versão atualizada com Calendário Económico e Filtro de Horário

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// --- Inputs ---
input string   group_trigger = "--- Main Triggers ---";
input double   InpXOffset     = 0.1;        // Extreme Offset (X)

input string   group_time       = "--- Trading Hours ---";
input bool     InpUseTimeFilter = true;     // Usar Filtro de Horário
input string   InpStartTime     = "01:00";  // Hora de Início (Servidor HH:MM)
input string   InpEndTime       = "23:00";  // Hora de Término (Servidor HH:MM)

input string   group_news       = "--- Auto News Filter ---";
input bool     InpUseNewsFilter = false;     // Ativar Filtro de Notícias (Calendário)
input int      InpNewsBeforeMin = 60;       // Pausar X minutos ANTES da notícia
input int      InpNewsAfterMin  = 30;       // Pausar X minutos DEPOIS da notícia
input int      InpNewsImpact    = 3;        // 3 = Alto Impacto (High)

input string   group_tp      = "--- Take Profit ---";
input double   InpYTP         = 1.0;        // Profit Target (Y)
input string   group_avg     = "--- Grid Management (Z) ---";
input double   InpZStep       = 6.8;        // Min Grid Distance (Z)
input int      InpMaxOrders   = 100;        // Max Orders

input string   group_mt5     = "--- MT5 Specifics ---";
input double   InpLotSize     = 0.01;       // Initial Lot Size
input int      InpVolumeDoubleStep = 25;    // Double Volume every N orders (0=Off)
input ulong    InpMagic       = 20260306;   // Magic Number

// Global Objects
CTrade         trade;
datetime       lastTradeBarTime = 0; // Para limitar 1 trade por barra

//+------------------------------------------------------------------+
//| Função para verificar o Horário de Negociação                    |
//+------------------------------------------------------------------+
bool IsTradingTime()
  {
   if(!InpUseTimeFilter) return true; // Se o filtro estiver desligado, permite sempre

   datetime now = TimeCurrent(); // Hora do servidor
   MqlDateTime dt;
   TimeToStruct(now, dt);

   int current_mins = dt.hour * 60 + dt.min;

   string start_parts[];
   string end_parts[];
   StringSplit(InpStartTime, ':', start_parts);
   StringSplit(InpEndTime, ':', end_parts);

   if(ArraySize(start_parts) < 2 || ArraySize(end_parts) < 2) return true; // Proteção contra formato inválido

   int start_mins = (int)StringToInteger(start_parts[0]) * 60 + (int)StringToInteger(start_parts[1]);
   int end_mins = (int)StringToInteger(end_parts[0]) * 60 + (int)StringToInteger(end_parts[1]);

   // Verifica se o horário ocorre no mesmo dia (ex: 08:00 às 17:00)
   if(start_mins < end_mins)
     {
      if(current_mins >= start_mins && current_mins < end_mins) return true;
     }
   // Verifica se o horário cruza a meia-noite (ex: 22:00 às 05:00)
   else
     {
      if(current_mins >= start_mins || current_mins < end_mins) return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Função para verificar o Calendário Económico do MQL5             |
//+------------------------------------------------------------------+
bool IsNewsTime()
  {
   if(!InpUseNewsFilter) return false;

   datetime now = TimeCurrent();
   // Calcula a janela: olha para trás (After) e para a frente (Before)
   datetime from = now - (InpNewsAfterMin * 60);
   datetime to   = now + (InpNewsBeforeMin * 60);

   MqlCalendarValue values[];

   // Puxa o histórico de valores do calendário nesse intervalo de tempo
   if(CalendarValueHistory(values, from, to) <= 0) return false;

   // Percorre os eventos encontrados na janela
   for(int i = 0; i < ArraySize(values); i++)
     {
      MqlCalendarEvent event;
      // Carrega os detalhes do evento para saber o país e a importância
      if(CalendarEventById(values[i].event_id, event))
        {
         // 840 é o Country ID dos Estados Unidos (USD)
         // event.importance 3 equivale a CALENDAR_IMPORTANCE_HIGH
         if(event.country_id == 840 && event.importance >= InpNewsImpact)
           {
            return true; // Encontrou notícia de alto impacto na nossa janela
           }
        }
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   // Define slippage aceitável
   trade.SetDeviationInPoints(30);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Obter preços atuais
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // 2. Obter High e Low da barra anterior
   double prev_high = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double prev_low  = iLow(_Symbol, PERIOD_CURRENT, 1);

   // 3. Analisar posições abertas E ordens pendentes
   int    openTrades = 0;
   long   positionType = -1;
   double totalVolume = 0.0;
   double weightedPriceSum = 0.0;
   double lastEntryPrice = 0.0;
   long   lastEntryTime = 0;

   // Loop através de todas as posições ATIVAS
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
        {
         openTrades++;
         positionType = PositionGetInteger(POSITION_TYPE); // 0 = Buy, 1 = Sell

         double vol = PositionGetDouble(POSITION_VOLUME);
         double price = PositionGetDouble(POSITION_PRICE_OPEN);

         totalVolume += vol;
         weightedPriceSum += (price * vol);

         long posTime = PositionGetInteger(POSITION_TIME_MSC);
         if(posTime > lastEntryTime)
           {
            lastEntryTime = posTime;
            lastEntryPrice = price;
           }
        }
     }

   // Loop através de todas as ordens PENDENTES (Limits)
   int pendingOrders = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
        {
         pendingOrders++;
        }
     }

   double avgPrice = (totalVolume > 0) ? (weightedPriceSum / totalVolume) : 0.0;

   // 4. --- LÓGICA DE SAÍDA E LIMPEZA (Sempre ativa, mesmo com notícias/horários restritos) ---

   // Se não há ordens abertas, mas sobraram ordens LIMIT (TP atingido), limpe tudo!
   if(openTrades == 0 && pendingOrders > 0)
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
           {
            trade.OrderDelete(ticket);
           }
        }
      Print("Grade finalizada! Ordens LIMIT restantes removidas.");
      return; // Sai do tick para recomeçar limpo no próximo
     }

   // Lógica de Take Profit para ordens ativas
   if(openTrades > 0)
     {
      double targetTP = 0.0;
      bool shouldCloseNow = false;

      double stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

      if(positionType == POSITION_TYPE_BUY)
        {
         targetTP = NormalizeDouble(avgPrice + InpYTP, _Digits);
         if(bid >= targetTP) shouldCloseNow = true;
        }
      else if(positionType == POSITION_TYPE_SELL)
        {
         targetTP = NormalizeDouble(avgPrice - InpYTP, _Digits);
         if(ask <= targetTP) shouldCloseNow = true;
        }

      // Fechamento de Emergência Híbrido (A mercado)
      if(shouldCloseNow)
        {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            ulong ticket = PositionGetTicket(i);
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
              {
               trade.PositionClose(ticket);
              }
           }
         Print("Alvo atingido! Posições fechadas a mercado.");
         Comment("");
         return;
        }

      // Modificação Dinâmica de TP (Coloca o TP no servidor)
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
           {
            double currentTP = PositionGetDouble(POSITION_TP);
            double currentSL = PositionGetDouble(POSITION_SL);

            if(MathAbs(currentTP - targetTP) > _Point)
              {
               bool isValidTP = true;
               if(positionType == POSITION_TYPE_BUY  && targetTP <= bid + stopsLevel) isValidTP = false;
               if(positionType == POSITION_TYPE_SELL && targetTP >= ask - stopsLevel) isValidTP = false;

               if(isValidTP)
                 {
                  trade.PositionModify(ticket, currentSL, targetTP);
                 }
              }
           }
        }
     }

   // 5. --- LÓGICA DE ENTRADA (Grade Inicial + LIMITS) ---

   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool can_enter_this_bar = (currentBarTime != lastTradeBarTime) || (openTrades == 0);

   bool common_sell_rule = (bid > prev_high + InpXOffset);
   bool common_buy_rule  = (ask < prev_low - InpXOffset);

   bool isNewsBlocking = IsNewsTime(); // Verifica o calendário
   bool isTradingTime = IsTradingTime(); // Verifica o horário de funcionamento

   // Só tentamos nova entrada se não houver NADA ativo e se todas as condições/filtros permitirem
   if(can_enter_this_bar && openTrades == 0 && pendingOrders == 0)
     {
      if(isTradingTime && !isNewsBlocking)
        {
         bool short_initial = common_sell_rule;
         bool long_initial  = common_buy_rule;

         // Executa Venda
         if(short_initial)
           {
            if(trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "Initial Short"))
              {
               lastTradeBarTime = currentBarTime;
               Print("Short Executed. Colocando ordens LIMIT...");

               for(int i = 1; i < InpMaxOrders; i++)
                 {
                  double limitPrice = NormalizeDouble(bid + (i * InpZStep), _Digits);
                  double limitLot = InpLotSize;
                  if(InpVolumeDoubleStep > 0)
                    {
                     int power = i / InpVolumeDoubleStep;
                     limitLot = NormalizeDouble(InpLotSize * MathPow(2, power), 2);
                    }
                  trade.SellLimit(limitLot, limitPrice, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "Grid Limit Sell");
                 }
              }
           }
         // Executa Compra
         else if(long_initial)
           {
            if(trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "Initial Long"))
              {
               lastTradeBarTime = currentBarTime;
               Print("Long Executed. Colocando ordens LIMIT...");

               for(int i = 1; i < InpMaxOrders; i++)
                 {
                  double limitPrice = NormalizeDouble(ask - (i * InpZStep), _Digits);
                  double limitLot = InpLotSize;
                  if(InpVolumeDoubleStep > 0)
                    {
                     int power = i / InpVolumeDoubleStep;
                     limitLot = NormalizeDouble(InpLotSize * MathPow(2, power), 2);
                    }
                  trade.BuyLimit(limitLot, limitPrice, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "Grid Limit Buy");
                 }
              }
           }
        }
     }

   // --- DASHBOARD VISUAL ---
   string dash = "=== XAUUSD Exhaustion Grid v1.70 ===\n";
   dash += "Ordens Abertas (Ativas): " + IntegerToString(openTrades) + "\n";
   dash += "Ordens Pendentes (Limits): " + IntegerToString(pendingOrders) + "\n\n";

   if(openTrades > 0)
     {
      dash += "Direção Atual: " + (positionType == POSITION_TYPE_BUY ? "COMPRA (Long)" : "VENDA (Short)") + "\n";
      dash += "Preço Médio Atual: " + DoubleToString(avgPrice, _Digits) + "\n";
      dash += "Take Profit Global: " + DoubleToString(positionType == POSITION_TYPE_BUY ? avgPrice + InpYTP : avgPrice - InpYTP, _Digits) + "\n\n";
      dash += "Aguardando preço atingir o TP ou acionar os LIMITS restantes.";
     }
   else if (pendingOrders > 0)
     {
      dash += "Limpando ordens pendentes residuais...\n";
     }
   else
     {
      if(!isTradingTime)
        {
         dash += "⏸️ EA PAUSADO: FORA DO HORÁRIO DE TRADING ⏸️\n";
         dash += "Horário permitido: " + InpStartTime + " às " + InpEndTime + " (Servidor)\n";
        }
      else if(isNewsBlocking)
        {
         dash += "⚠️ EA PAUSADO: FILTRO DE NOTÍCIAS ATIVO ⚠️\n";
         dash += "Notícia de Alto Impacto (EUA) no Calendário.\n";
         dash += "Aguardando janela de segurança passar...\n";
        }
      else
        {
         dash += "✅ Mercado Seguro. Aguardando Oportunidade...\n\n";
         dash += "Rompeu High Anterior + Offset? " + (common_sell_rule ? "SIM (Apto a Vender)\n" : "NÃO\n");
         dash += "Rompeu Low Anterior + Offset? " + (common_buy_rule ? "SIM (Apto a Comprar)\n" : "NÃO\n");
        }
     }

   Comment(dash);
  }