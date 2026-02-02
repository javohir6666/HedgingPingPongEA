//+------------------------------------------------------------------+
//|                                            HedgingPingPongEA.mq5 |
//|                               Copyright 2025, Javohir Abdullayev |
//|                                                      Version 4.0 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Javohir Abdullayev"
#property link      "https://pycoder.uz"
#property version   "4.0"
#property description "Smart Recovery Hedging (No Martingale)"

#include <Trade/Trade.mqh>
#include "Modules\Dashboard.mqh"

//--- EA Inputs
input group   "Trade Settings"
input ulong   InpMagicNumber       = 13579; 
input double  InpStartLot          = 0.01;  // Boshlang'ich Lot
input double  InpProfitPerCycle    = 1.0;   // Har bir sikldan qancha dollar foyda kerak?

//--- Dynamic Settings (ATR)
input group   "Dynamic Parameters (ATR)"
input bool    InpUseDynamicParams  = true;  
input int     InpATRPeriod         = 14;    
input double  InpMultDistance      = 1.5;   // Distance Multiplier
input double  InpMultProfit        = 4.0;   // Profit Multiplier
input int     InpMinDistance       = 100;   // Min points

//--- Fixed Fallback Settings
input group   "Fixed Settings (Fallback)"
input int     InpFixedDist         = 200;   
input int     InpFixedTP           = 800;   // Profit Leg

//--- Auto Entry Settings
input group   "Auto Entry Settings"
input bool    InpEnableAutoTrade   = true;  
input int     InpMAPeriodFast      = 50;    
input int     InpMAPeriodSlow      = 200;   
input int     InpADXPeriod         = 14;    
input int     InpADXLevel          = 25;    

//--- Dashboard Settings
input group   "Dashboard Settings"
input bool    InpDashboardOn       = true;  
input ENUM_DASHBOARD_CORNER InpDashboardCorner = UPPER_LEFT; 
input ENUM_DASHBOARD_THEME InpDashboardTheme = THEME_NIGHT; 
input int     InpDashboardX        = 20;    
input int     InpDashboardY        = 50;    
input int     InpDashboardWidth    = 300;   

//--- Global variables
CTrade      g_trade;
CDashboard   g_dashboard;
bool        g_is_active = false;
ulong       g_initial_position_ticket = 0;
int         g_orders_count = 0; // Nechinchi qadamdagi order

//--- Dynamic Values
int         g_current_Dist = 0;
int         g_current_Profit = 0;
int         g_current_FullSL = 0;

//--- Indicator Handles
int         g_hMA_Fast, g_hMA_Slow, g_hADX, g_hATR;

//--- Forward declarations
void CloseAllAndReset();
void PlaceNextPendingOrder(ulong position_ticket);
void CheckAndOpenFirstTrade();
void CheckSequenceState();
void CalculateDynamicParams();
double CalculateSmartLot(double target_price_level); // YANGI FUNKSIYA

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetMarginMode();
   g_trade.SetTypeFillingBySymbol(_Symbol);
   
   if(InpEnableAutoTrade) {
      g_hMA_Fast = iMA(_Symbol, _Period, InpMAPeriodFast, 0, MODE_SMA, PRICE_CLOSE);
      g_hMA_Slow = iMA(_Symbol, _Period, InpMAPeriodSlow, 0, MODE_SMA, PRICE_CLOSE);
      g_hADX     = iADX(_Symbol, _Period, InpADXPeriod);
   }
   if(InpUseDynamicParams) g_hATR = iATR(_Symbol, _Period, InpATRPeriod);
   
   if(InpDashboardOn)
      g_dashboard.Create(ChartID(), "HPP_SMART", InpDashboardX, InpDashboardY, InpDashboardWidth, InpDashboardCorner, InpDashboardTheme);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(InpDashboardOn) g_dashboard.Destroy();
   IndicatorRelease(g_hMA_Fast); IndicatorRelease(g_hMA_Slow);
   IndicatorRelease(g_hADX); IndicatorRelease(g_hATR);
   if(reason == REASON_REMOVE) CloseAllAndReset();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckSequenceState();

   if(InpEnableAutoTrade && !g_is_active) CheckAndOpenFirstTrade();

   if(InpDashboardOn) g_dashboard.Update(g_initial_position_ticket, InpMagicNumber);
}

//+------------------------------------------------------------------+
//| YANGI: Aqlli Lot Hisoblash (Smart Lot)                           |
//+------------------------------------------------------------------+
double CalculateSmartLot(double target_price_level)
{
   double total_potential_loss = 0;
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   // 1. Agar hozirgi barcha ochiq pozitsiyalar "Target Price" gacha yursa, qancha zarar qiladi?
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      CPositionInfo pos;
      if(pos.SelectByIndex(i))
      {
         if(pos.Symbol() == _Symbol && (pos.Magic() == InpMagicNumber || pos.Ticket() == g_initial_position_ticket))
         {
            double diff = 0;
            // Agar Buy bo'lsa va Target pastda bo'lsa -> Zarar
            if(pos.PositionType() == POSITION_TYPE_BUY)
               diff = target_price_level - pos.PriceOpen(); // Masalan: 1.0900 - 1.1000 = -0.0100
            else
               diff = pos.PriceOpen() - target_price_level;
            
            // Pulinga o'giramiz
            double profit_money = (diff / tick_size) * tick_value * pos.Volume();
            total_potential_loss += profit_money;
         }
      }
   }
   
   // Biz faqat zararni hisoblaymiz (foyda minus bo'ladi)
   // Agar total_potential_loss musbat bo'lsa, demak allaqachon foydamiz, lot 0.01 qolaversin
   if(total_potential_loss >= 0) return InpStartLot;
   
   // Zarar manfiy sonda, uni musbatga aylantiramiz
   double loss_to_recover = MathAbs(total_potential_loss);
   
   // Qo'shimcha foyda qo'shamiz
   double required_profit = loss_to_recover + InpProfitPerCycle;
   
   // 2. Ushbu foydani olish uchun bizda qancha masofa bor?
   // Masofa = g_current_Profit (punktlarda)
   double profit_points = (double)g_current_Profit;
   
   // 3. Lotni hisoblash: Pul / (Punktlar * TickValue)
   double calculated_lot = required_profit / (profit_points * tick_value);
   
   // 4. Lotni broker standartiga to'g'irlash
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   calculated_lot = MathCeil(calculated_lot / step) * step; // Yuqoriga yaxlitlaymiz (xavfsizlik uchun)
   
   if(calculated_lot < min_lot) calculated_lot = min_lot;
   if(calculated_lot > max_lot) calculated_lot = max_lot;
   
   Print("Smart Lot Calc: LossToRecover=", DoubleToString(loss_to_recover, 2), 
         " | DistPoints=", profit_points, 
         " | CalcLot=", calculated_lot);
         
   return calculated_lot;
}

//+------------------------------------------------------------------+
//| Dinamik Parametrlar va Sinxronizatsiya                           |
//+------------------------------------------------------------------+
void CalculateDynamicParams()
{
   if(!InpUseDynamicParams) {
      g_current_Dist   = InpFixedDist;
      g_current_Profit = InpFixedTP;
      g_current_FullSL = InpFixedDist + InpFixedTP; 
   } else {
      double atr_values[]; ArraySetAsSeries(atr_values, true);
      if(CopyBuffer(g_hATR, 0, 0, 1, atr_values) > 0) {
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         int atr_points = (int)(atr_values[0] / point);
         
         g_current_Dist = (int)(atr_points * InpMultDistance);
         if(g_current_Dist < InpMinDistance) g_current_Dist = InpMinDistance;

         g_current_Profit = (int)(atr_points * InpMultProfit);
         g_current_FullSL = g_current_Dist + g_current_Profit;
         
         // Agar ATR juda katta bo'lsa va Profit masofasi 50 punktdan kam bo'lsa, matematik xato bo'lmasligi uchun
         if(g_current_Profit < 50) g_current_Profit = 50; 
      } else {
         g_current_Dist = InpFixedDist; g_current_Profit = InpFixedTP; g_current_FullSL = InpFixedDist + InpFixedTP;
      }
   }
}

//+------------------------------------------------------------------+
//| Order joylashtirish (Smart Lot bilan)                            |
//+------------------------------------------------------------------+
void PlaceNextPendingOrder(ulong position_ticket)
{
   CPositionInfo pos;
   if(!pos.SelectByTicket(position_ticket)) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // SL/TP Sinxronizatsiya
   double sl, tp;
   if(pos.PositionType() == POSITION_TYPE_BUY) {
      sl = pos.PriceOpen() - g_current_FullSL * point;
      tp = pos.PriceOpen() + g_current_Profit * point;
   } else {
      sl = pos.PriceOpen() + g_current_FullSL * point;
      tp = pos.PriceOpen() - g_current_Profit * point;
   }
   if(MathAbs(pos.StopLoss()-sl)>point || MathAbs(pos.TakeProfit()-tp)>point)
      g_trade.PositionModify(position_ticket, sl, tp);

   // --- SMART LOT HISOBLASH ---
   // Keyingi order qayerda ochilishini va uning TP si qayerda bo'lishini aniqlaymiz
   double pending_price = 0;
   double target_tp_price = 0;
   ENUM_ORDER_TYPE order_type;
   
   if(pos.PositionType() == POSITION_TYPE_BUY) {
      order_type = ORDER_TYPE_SELL_STOP;
      pending_price = pos.PriceOpen() - g_current_Dist * point;
      target_tp_price = pending_price - g_current_Profit * point; // Sell TP pastda bo'ladi
   } else {
      order_type = ORDER_TYPE_BUY_STOP;
      pending_price = pos.PriceOpen() + g_current_Dist * point;
      target_tp_price = pending_price + g_current_Profit * point; // Buy TP tepada bo'ladi
   }

   // Shu target_tp_price ga yetganda barcha zararlarni yopadigan lotni topamiz
   double smart_lot = CalculateSmartLot(target_tp_price);
   
   // Order qo'yish
   double p_sl = 0, p_tp = 0;
   if(order_type == ORDER_TYPE_BUY_STOP) {
      p_sl = pending_price - g_current_FullSL * point;
      p_tp = pending_price + g_current_Profit * point;
   } else {
      p_sl = pending_price + g_current_FullSL * point;
      p_tp = pending_price - g_current_Profit * point;
   }
   
   g_trade.OrderOpen(_Symbol, order_type, smart_lot, 0.0, 
      NormalizeDouble(pending_price, digits), 
      NormalizeDouble(p_sl, digits), 
      NormalizeDouble(p_tp, digits), 
      ORDER_TIME_GTC, 0, "Hedge Smart");
}

//+------------------------------------------------------------------+
//| Auto Trade                                                       |
//+------------------------------------------------------------------+
void CheckAndOpenFirstTrade()
{
   double maFast[], maSlow[], adxMain[];
   ArraySetAsSeries(maFast, true); ArraySetAsSeries(maSlow, true); ArraySetAsSeries(adxMain, true);

   if(CopyBuffer(g_hMA_Fast, 0, 0, 2, maFast) < 2) return;
   if(CopyBuffer(g_hMA_Slow, 0, 0, 2, maSlow) < 2) return;
   if(CopyBuffer(g_hADX, 0, 0, 2, adxMain) < 2) return;

   if(adxMain[0] < InpADXLevel) return;

   CalculateDynamicParams(); // Parametrlarni yangilash

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(maFast[0] > maSlow[0]) {
      double sl = ask - g_current_FullSL * point;
      double tp = ask + g_current_Profit * point;
      g_trade.Buy(InpStartLot, _Symbol, ask, sl, tp, "Auto Buy");
   } else if(maFast[0] < maSlow[0]) {
      double sl = bid + g_current_FullSL * point;
      double tp = bid - g_current_Profit * point;
      g_trade.Sell(InpStartLot, _Symbol, bid, sl, tp, "Auto Sell");
   }
}

//+------------------------------------------------------------------+
//| Tranzaksiya                                                      |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
    if (trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
    if (trans.symbol != _Symbol) return;

    CPositionInfo pos_info;
    if (!pos_info.SelectByTicket(trans.position)) return;

    if (!g_is_active && (pos_info.Magic() == 0 || pos_info.Magic() == InpMagicNumber)) {
        CalculateDynamicParams(); // Muhim!
        g_is_active = true;
        g_initial_position_ticket = pos_info.Ticket();
        g_orders_count = 1;
        PlaceNextPendingOrder(pos_info.Ticket());
    } else if (g_is_active && pos_info.Magic() == InpMagicNumber && pos_info.Ticket() == trans.position) {
        if (pos_info.Ticket() != g_initial_position_ticket) {
           g_orders_count++;
           PlaceNextPendingOrder(pos_info.Ticket());
        }
    }
}

//+------------------------------------------------------------------+
//| State Cleaner                                                    |
//+------------------------------------------------------------------+
void CheckSequenceState()
{
   if (g_is_active) {
      bool exists = false;
      for(int i=PositionsTotal()-1; i>=0; i--) {
         CPositionInfo p;
         if(p.SelectByIndex(i)) {
            if(p.Symbol()==_Symbol && (p.Magic()==InpMagicNumber || p.Ticket()==g_initial_position_ticket)) {
               exists = true; break;
            }
         }
      }
      if (!exists) CloseAllAndReset();
   }
}

void CloseAllAndReset()
{
   for(int i=PositionsTotal()-1; i>=0; i--) {
      CPositionInfo p;
      if(p.SelectByIndex(i)) {
         if(p.Symbol()==_Symbol && (p.Magic()==InpMagicNumber || p.Ticket()==g_initial_position_ticket))
            g_trade.PositionClose(p.Ticket());
      }
   }
   for(int i=OrdersTotal()-1; i>=0; i--) {
      COrderInfo o;
      if(o.SelectByIndex(i)) {
         if(o.Symbol()==_Symbol && o.Magic()==InpMagicNumber) g_trade.OrderDelete(o.Ticket());
      }
   }
   g_is_active = false;
   g_initial_position_ticket = 0;
   g_orders_count = 0;
}
