//+------------------------------------------------------------------+
//|                  SignalHarvesterProviderDD_Complete.mq4          |
//|         Per-Provider Peak DD + All Reset Methods Integrated      |
//|                    PRODUCTION READY v3.0                         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "3.0"
#property strict

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - FTMO $200K ACCOUNT CONFIGURATION              |
//+------------------------------------------------------------------+
input string ProviderDDSettings = "Provider1,12.0,18.0,22.0;Provider2,12.0,18.0,22.0";
// Format: ProviderID,warnDD%,critDD%,emergDD%;...
// Accommodates signals up to 20% Historical DD
// 12% = Early warning, 18% = Damage control, 22% = Hard stop (exceeded historical)

// Absolute Loss Protection - FTMO SAFETY (10% total account DD limit!)
input double MaxProviderLossAmount = 2500.0;     // $2,500 per provider (1.25% of $200K)
input double MaxProviderLossPercent = 1.5;       // 1.5% max loss per provider (FTMO-appropriate)
input bool   EnableAbsoluteLossProtection = true; // CRITICAL: Protects against bad signals
input int    StateSaveIntervalSeconds = 300;
input int    RecalcClosedPLIntervalSec = 600;
input bool   EnableDebugLogs = true;
input bool   ShowChartButtons = true;           // Show reset buttons on chart
input bool   EnableKeyboardShortcuts = true;    // Enable keyboard shortcuts

// UI Settings
input int    ButtonXPosition = 20;
input int    ButtonYPosition = 50;
input color  ButtonColorActive = clrDarkGreen;
input color  ButtonColorBlocked = clrCrimson;

//+------------------------------------------------------------------+
//| STRUCTS / GLOBALS                                                |
//+------------------------------------------------------------------+
struct ProviderStats
{
   string   providerId;
   double   peakEquity;
   double   currentEquity;
   double   closedPL;
   double   floatingPL;
   double   warnDDPercent;
   double   critDDPercent;
   double   emergDDPercent;
   bool     killSwitchTriggered;
   datetime lastWarnTime;
   int      tradesCount;
};

struct TradeInfo
{
   int      ticket;
   string   providerId;
   string   symbol;
   int      orderType;
   double   lots;
   double   openPrice;
   double   sl;
   double   tp;
   datetime openTime;
   string   comment;
   int      magic;
   double   floatingPL;
};

ProviderStats g_ProviderStats[];
TradeInfo     g_OpenTrades[];
datetime      g_LastStateSave = 0;
datetime      g_LastClosedPLUpdate = 0;
datetime      g_LastButtonUpdate = 0;
string        g_AuditFileName;

//+------------------------------------------------------------------+
//| Helper: Debug Log                                                |
//+------------------------------------------------------------------+
void DebugLog(string msg)
{
   if(EnableDebugLogs)
      Print("[SHRA] ", msg);
}

//+------------------------------------------------------------------+
//| Parse Provider DD Settings                                       |
//+------------------------------------------------------------------+
bool ParseProviderDDSettings()
{
   ArrayResize(g_ProviderStats, 0);
   
   string raw = ProviderDDSettings;
   int providerCount = 0;
   
   while(StringLen(raw) > 0)
   {
      int semiPos = StringFind(raw, ";");
      string block = (semiPos >= 0) ? StringSubstr(raw, 0, semiPos) : raw;
      
      string parts[];
      int numParts = StringSplit(block, ',', parts);
      
      if(numParts == 4)
      {
         string pid = parts[0];
         double warn = StringToDouble(parts[1]);
         double crit = StringToDouble(parts[2]);
         double emerg = StringToDouble(parts[3]);
         
         if(warn > 0 && crit > warn && emerg > crit)
         {
            ArrayResize(g_ProviderStats, providerCount + 1);
            
            g_ProviderStats[providerCount].providerId = pid;
            g_ProviderStats[providerCount].warnDDPercent = warn;
            g_ProviderStats[providerCount].critDDPercent = crit;
            g_ProviderStats[providerCount].emergDDPercent = emerg;
            g_ProviderStats[providerCount].peakEquity = 0.0;
            g_ProviderStats[providerCount].currentEquity = 0.0;
            g_ProviderStats[providerCount].closedPL = 0.0;
            g_ProviderStats[providerCount].floatingPL = 0.0;
            g_ProviderStats[providerCount].killSwitchTriggered = false;
            g_ProviderStats[providerCount].lastWarnTime = 0;
            g_ProviderStats[providerCount].tradesCount = 0;
            
            providerCount++;
            
            DebugLog(StringFormat("Parsed provider: %s (Warn:%.1f%%, Crit:%.1f%%, Emerg:%.1f%%)",
                    pid, warn, crit, emerg));
         }
      }
      
      if(semiPos < 0) break;
      raw = StringSubstr(raw, semiPos + 1);
   }
   
   DebugLog(StringFormat("Total providers configured: %d", providerCount));
   return (providerCount > 0);
}

//+------------------------------------------------------------------+
//| Find Provider Index                                              |
//+------------------------------------------------------------------+
int FindProviderStatsIndex(string providerId)
{
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      if(g_ProviderStats[i].providerId == providerId)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Ensure Provider Exists                                           |
//+------------------------------------------------------------------+
int EnsureProviderExists(string providerId)
{
   int idx = FindProviderStatsIndex(providerId);
   if(idx >= 0) return idx;
   
   int size = ArraySize(g_ProviderStats);
   ArrayResize(g_ProviderStats, size + 1);
   
   g_ProviderStats[size].providerId = providerId;
   g_ProviderStats[size].warnDDPercent = 2.5;
   g_ProviderStats[size].critDDPercent = 3.5;
   g_ProviderStats[size].emergDDPercent = 4.5;
   g_ProviderStats[size].peakEquity = 0.0;
   g_ProviderStats[size].currentEquity = 0.0;
   g_ProviderStats[size].closedPL = 0.0;
   g_ProviderStats[size].floatingPL = 0.0;
   g_ProviderStats[size].killSwitchTriggered = false;
   g_ProviderStats[size].lastWarnTime = 0;
   g_ProviderStats[size].tradesCount = 0;
   
   DebugLog(StringFormat("Auto-added provider: %s", providerId));
   return size;
}

//+------------------------------------------------------------------+
//| Identify Provider from Trade                                     |
//+------------------------------------------------------------------+
string IdentifyProvider(int magic, string comment)
{
   // ONLY match configured provider IDs in comments
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      if(StringFind(comment, g_ProviderStats[i].providerId) >= 0)
         return g_ProviderStats[i].providerId;
   }
   
   // Return empty string if no matching provider found
   // This filters out trades without proper provider identification
   return "";
}

//+------------------------------------------------------------------+
//| Scan Open Orders                                                 |
//+------------------------------------------------------------------+
void ScanOpenOrders()
{
   ArrayResize(g_OpenTrades, 0);
   
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderType() > OP_SELL) continue;
      
      string providerId = IdentifyProvider(OrderMagicNumber(), OrderComment());
      
      // Skip trades without valid provider identification
      if(StringLen(providerId) == 0)
      {
         DebugLog(StringFormat("Skipping trade #%d (Magic:%d) - no matching provider in comment: %s",
                              OrderTicket(), OrderMagicNumber(), OrderComment()));
         continue;
      }
      
      int size = ArraySize(g_OpenTrades);
      ArrayResize(g_OpenTrades, size + 1);
      
      g_OpenTrades[size].ticket = OrderTicket();
      g_OpenTrades[size].providerId = providerId;
      g_OpenTrades[size].symbol = OrderSymbol();
      g_OpenTrades[size].orderType = OrderType();
      g_OpenTrades[size].lots = OrderLots();
      g_OpenTrades[size].openPrice = OrderOpenPrice();
      g_OpenTrades[size].sl = OrderStopLoss();
      g_OpenTrades[size].tp = OrderTakeProfit();
      g_OpenTrades[size].openTime = OrderOpenTime();
      g_OpenTrades[size].comment = OrderComment();
      g_OpenTrades[size].magic = OrderMagicNumber();
      g_OpenTrades[size].floatingPL = OrderProfit() + OrderSwap() + OrderCommission();
   }
}

//+------------------------------------------------------------------+
//| Update Provider Equity Stats                                     |
//+------------------------------------------------------------------+
void UpdateProviderEquityStats()
{
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      g_ProviderStats[i].floatingPL = 0.0;
      g_ProviderStats[i].tradesCount = 0;
   }
   
   for(int i = 0; i < ArraySize(g_OpenTrades); i++)
   {
      string pid = g_OpenTrades[i].providerId;
      int idx = EnsureProviderExists(pid);
      
      g_ProviderStats[idx].floatingPL += g_OpenTrades[i].floatingPL;
      g_ProviderStats[idx].tradesCount++;
   }
   
   if(TimeCurrent() - g_LastClosedPLUpdate >= RecalcClosedPLIntervalSec)
   {
      for(int i = 0; i < ArraySize(g_ProviderStats); i++)
         g_ProviderStats[i].closedPL = 0.0;
      
      for(int i = 0; i < OrdersHistoryTotal(); i++)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
         if(OrderType() > OP_SELL) continue;
         
         string pid = IdentifyProvider(OrderMagicNumber(), OrderComment());
         
         // Skip closed trades without valid provider identification
         if(StringLen(pid) == 0) continue;
         
         int idx = EnsureProviderExists(pid);
         
         g_ProviderStats[idx].closedPL += OrderProfit() + OrderSwap() + OrderCommission();
      }
      
      g_LastClosedPLUpdate = TimeCurrent();
   }
   
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      g_ProviderStats[i].currentEquity = g_ProviderStats[i].closedPL + 
                                         g_ProviderStats[i].floatingPL;
      
      // Update peak only on realized profits (closed trades)
      // This prevents premature exits from floating P&L volatility
      if(g_ProviderStats[i].closedPL > g_ProviderStats[i].peakEquity)
         g_ProviderStats[i].peakEquity = g_ProviderStats[i].closedPL;
   }
}

//+------------------------------------------------------------------+
//| Append to CSV Audit Log                                          |
//+------------------------------------------------------------------+
void AppendToAuditLog(string providerId, string eventType, double ddPercent, string details)
{
   int handle = FileOpen(g_AuditFileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   
   if(handle == INVALID_HANDLE) return;
   
   bool needsHeader = (FileSize(handle) == 0);
   FileSeek(handle, 0, SEEK_END);
   
   if(needsHeader)
   {
      FileWriteString(handle, "Timestamp,Account,Provider,Event,PeakEquity,CurrentEquity,DDPercent,OpenTrades,Details\n");
   }
   
   string safeProviderId = providerId;
   StringReplace(safeProviderId, "\"", "\"\"");
   if(StringFind(safeProviderId, ",") >= 0)
      safeProviderId = "\"" + safeProviderId + "\"";
   
   string safeDetails = details;
   StringReplace(safeDetails, "\"", "\"\"");
   if(StringFind(safeDetails, ",") >= 0)
      safeDetails = "\"" + safeDetails + "\"";
   
   int idx = FindProviderStatsIndex(providerId);
   double peakEquity = (idx >= 0) ? g_ProviderStats[idx].peakEquity : 0.0;
   double currentEquity = (idx >= 0) ? g_ProviderStats[idx].currentEquity : 0.0;
   int openTrades = (idx >= 0) ? g_ProviderStats[idx].tradesCount : 0;
   
   string row = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "," +
                IntegerToString(AccountNumber()) + "," +
                safeProviderId + "," +
                eventType + "," +
                DoubleToString(peakEquity, 2) + "," +
                DoubleToString(currentEquity, 2) + "," +
                DoubleToString(ddPercent, 2) + "," +
                IntegerToString(openTrades) + "," +
                safeDetails + "\n";
   
   FileWriteString(handle, row);
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Check Provider Floating DD                                       |
//+------------------------------------------------------------------+
void CheckProviderFloatingDD()
{
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      string pid = g_ProviderStats[i].providerId;
      
      if(g_ProviderStats[i].killSwitchTriggered) continue;
      
      double peak = g_ProviderStats[i].peakEquity;
      double current = g_ProviderStats[i].currentEquity;
      
      // ═══════════════════════════════════════════════════════════════
      // ABSOLUTE LOSS PROTECTION (for providers that never profit)
      // ═══════════════════════════════════════════════════════════════
      if(EnableAbsoluteLossProtection && current < 0)
      {
         bool triggerAbsoluteLoss = false;
         string lossReason = "";
         
         // Check dollar-based limit
         if(current <= -MaxProviderLossAmount)
         {
            triggerAbsoluteLoss = true;
            lossReason = StringFormat("Lost $%.2f (limit: $%.2f)", -current, MaxProviderLossAmount);
         }
         
         // Check percentage-based limit
         double accountEquity = AccountEquity();
         if(accountEquity > 0)
         {
            double lossPercent = (-current / accountEquity) * 100.0;
            if(lossPercent >= MaxProviderLossPercent)
            {
               triggerAbsoluteLoss = true;
               lossReason = StringFormat("Lost %.2f%% of account (limit: %.2f%%)", 
                                        lossPercent, MaxProviderLossPercent);
            }
         }
         
         if(triggerAbsoluteLoss)
         {
            Print(StringFormat("🚨 ABSOLUTE LOSS LIMIT: Provider %s - %s - KILL SWITCH!", 
                              pid, lossReason));
            
            int closedCount = 0;
            for(int j = ArraySize(g_OpenTrades) - 1; j >= 0; j--)
            {
               if(g_OpenTrades[j].providerId == pid)
               {
                  if(CloseOrder(g_OpenTrades[j].ticket, "Absolute loss limit breach"))
                     closedCount++;
               }
            }
            
            g_ProviderStats[i].killSwitchTriggered = true;
            
            AppendToAuditLog(pid, "ABSOLUTE_LOSS_KILLSWITCH", 0.0,
                            StringFormat("%s - Closed %d trades", lossReason, closedCount));
            
            Alert(StringFormat("Provider %s: KILL SWITCH - %s!", pid, lossReason));
            continue;
         }
      }
      
      // ═══════════════════════════════════════════════════════════════
      // PEAK-BASED DD PROTECTION (for providers with profit history)
      // ═══════════════════════════════════════════════════════════════
      if(peak <= 0) continue;  // Skip peak DD if provider never profitable
      
      double dd = ((peak - current) / peak) * 100.0;
      
      if(dd <= 0) continue;
      
      // EMERGENCY
      if(dd >= g_ProviderStats[i].emergDDPercent)
      {
         Print(StringFormat("🚨 EMERGENCY: Provider %s DD %.2f%% - KILL SWITCH!", pid, dd));
         
         int closedCount = 0;
         for(int j = ArraySize(g_OpenTrades) - 1; j >= 0; j--)
         {
            if(g_OpenTrades[j].providerId == pid)
            {
               if(CloseOrder(g_OpenTrades[j].ticket, "Provider emergency DD"))
                  closedCount++;
            }
         }
         
         g_ProviderStats[i].killSwitchTriggered = true;
         
         AppendToAuditLog(pid, "EMERGENCY_KILLSWITCH", dd,
                         StringFormat("Closed %d trades, kill switch engaged", closedCount));
         
         Alert(StringFormat("Provider %s: KILL SWITCH at %.2f%% DD!", pid, dd));
         continue;
      }
      
      // CRITICAL
      if(dd >= g_ProviderStats[i].critDDPercent)
      {
         Print(StringFormat("🔴 CRITICAL: Provider %s DD %.2f%% - Trimming!", pid, dd));
         
         int closedCount = CloseWorstProviderTrades(pid, 0.2);
         
         AppendToAuditLog(pid, "CRITICAL_TRIM", dd,
                         StringFormat("Closed %d worst trades", closedCount));
         continue;
      }
      
      // WARNING
      if(dd >= g_ProviderStats[i].warnDDPercent)
      {
         if(TimeCurrent() - g_ProviderStats[i].lastWarnTime >= 300)
         {
            Print(StringFormat("⚠️ WARNING: Provider %s DD %.2f%%", pid, dd));
            AppendToAuditLog(pid, "WARNING", dd, "Provider approaching DD threshold");
            g_ProviderStats[i].lastWarnTime = TimeCurrent();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close Worst Provider Trades                                      |
//+------------------------------------------------------------------+
int CloseWorstProviderTrades(string providerId, double percent)
{
   int indices[];
   int count = 0;
   
   for(int i = 0; i < ArraySize(g_OpenTrades); i++)
   {
      if(g_OpenTrades[i].providerId == providerId)
      {
         ArrayResize(indices, count + 1);
         indices[count] = i;
         count++;
      }
   }
   
   if(count == 0) return 0;
   
   for(int i = 0; i < count - 1; i++)
   {
      for(int j = 0; j < count - i - 1; j++)
      {
         if(g_OpenTrades[indices[j]].floatingPL > g_OpenTrades[indices[j+1]].floatingPL)
         {
            int temp = indices[j];
            indices[j] = indices[j+1];
            indices[j+1] = temp;
         }
      }
   }
   
   int toClose = (int)MathCeil(count * percent);
   int closedCount = 0;
   
   for(int i = 0; i < toClose && i < count; i++)
   {
      int idx = indices[i];
      if(CloseOrder(g_OpenTrades[idx].ticket, "Provider DD trim"))
         closedCount++;
   }
   
   return closedCount;
}

//+------------------------------------------------------------------+
//| Close Order                                                       |
//+------------------------------------------------------------------+
bool CloseOrder(int ticket, string reason)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return false;
   
   double closePrice = (OrderType() == OP_BUY) ? 
                       MarketInfo(OrderSymbol(), MODE_BID) : 
                       MarketInfo(OrderSymbol(), MODE_ASK);
   
   for(int i = 0; i < 3; i++)
   {
      if(OrderClose(ticket, OrderLots(), closePrice, 5, clrRed))
      {
         DebugLog(StringFormat("Closed #%d: %s", ticket, reason));
         return true;
      }
      Sleep(1000);
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Reset Provider Kill Switch                                       |
//+------------------------------------------------------------------+
void ResetProviderKillSwitch(string providerId)
{
   int idx = FindProviderStatsIndex(providerId);
   
   if(idx < 0)
   {
      DebugLog(StringFormat("Provider %s not found", providerId));
      return;
   }
   
   if(!g_ProviderStats[idx].killSwitchTriggered)
   {
      DebugLog(StringFormat("Provider %s kill switch not active", providerId));
      return;
   }
   
   double oldPeak = g_ProviderStats[idx].peakEquity;
   double currentEquity = g_ProviderStats[idx].currentEquity;
   
   // Reset peak to current equity to give provider fresh start
   g_ProviderStats[idx].peakEquity = currentEquity;
   g_ProviderStats[idx].killSwitchTriggered = false;
   
   AppendToAuditLog(providerId, "KILLSWITCH_RESET", 0.0, 
                   StringFormat("Kill switch reset - Peak reset from %.2f to %.2f", oldPeak, currentEquity));
   
   Alert(StringFormat("Provider %s: Kill switch RESET (Peak: $%.2f → $%.2f)", providerId, oldPeak, currentEquity));
   DebugLog(StringFormat("Kill switch reset: %s (Peak reset to current equity)", providerId));
}

//+------------------------------------------------------------------+
//| Save State to GlobalVariables                                    |
//+------------------------------------------------------------------+
void SavePersistedState()
{
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      string prefix = "SHRA_" + IntegerToString(AccountNumber()) + "_" + 
                      g_ProviderStats[i].providerId + "_";
      
      GlobalVariableSet(prefix + "PeakEquity", g_ProviderStats[i].peakEquity);
      GlobalVariableSet(prefix + "KillSwitch", g_ProviderStats[i].killSwitchTriggered ? 1.0 : 0.0);
   }
}

//+------------------------------------------------------------------+
//| Load State from GlobalVariables                                  |
//+------------------------------------------------------------------+
void LoadPersistedState()
{
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      string prefix = "SHRA_" + IntegerToString(AccountNumber()) + "_" + 
                      g_ProviderStats[i].providerId + "_";
      
      if(GlobalVariableCheck(prefix + "PeakEquity"))
      {
         g_ProviderStats[i].peakEquity = GlobalVariableGet(prefix + "PeakEquity");
      }
      
      if(GlobalVariableCheck(prefix + "KillSwitch"))
      {
         g_ProviderStats[i].killSwitchTriggered = (GlobalVariableGet(prefix + "KillSwitch") > 0);
      }
   }
}

//+------------------------------------------------------------------+
//| CREATE CHART BUTTONS                                             |
//+------------------------------------------------------------------+
void CreateChartButtons()
{
   if(!ShowChartButtons) return;
   
   int xPos = ButtonXPosition;
   int yPos = ButtonYPosition;
   int btnWidth = 180;
   int btnHeight = 28;
   int spacing = 33;
   
   // Title label
   string titleLabel = "SHRA_Title";
   if(ObjectCreate(0, titleLabel, OBJ_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, titleLabel, OBJPROP_XDISTANCE, xPos);
      ObjectSetInteger(0, titleLabel, OBJPROP_YDISTANCE, yPos - 25);
      ObjectSetString(0, titleLabel, OBJPROP_TEXT, "🛡️ Provider Kill Switch Control");
      ObjectSetInteger(0, titleLabel, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, titleLabel, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, titleLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   }
   
   // Provider buttons
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      string btnName = "SHRA_btnReset_" + g_ProviderStats[i].providerId;
      
      if(ObjectCreate(0, btnName, OBJ_BUTTON, 0, 0, 0))
      {
         ObjectSetInteger(0, btnName, OBJPROP_XDISTANCE, xPos);
         ObjectSetInteger(0, btnName, OBJPROP_YDISTANCE, yPos + (i * spacing));
         ObjectSetInteger(0, btnName, OBJPROP_XSIZE, btnWidth);
         ObjectSetInteger(0, btnName, OBJPROP_YSIZE, btnHeight);
         ObjectSetInteger(0, btnName, OBJPROP_FONTSIZE, 9);
         ObjectSetInteger(0, btnName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, btnName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, btnName, OBJPROP_HIDDEN, false);
      }
   }
   
   // Reset ALL button
   string resetAllBtn = "SHRA_btnResetAll";
   int allBtnY = yPos + (ArraySize(g_ProviderStats) * spacing) + 10;
   
   if(ObjectCreate(0, resetAllBtn, OBJ_BUTTON, 0, 0, 0))
   {
      ObjectSetInteger(0, resetAllBtn, OBJPROP_XDISTANCE, xPos);
      ObjectSetInteger(0, resetAllBtn, OBJPROP_YDISTANCE, allBtnY);
      ObjectSetInteger(0, resetAllBtn, OBJPROP_XSIZE, btnWidth);
      ObjectSetInteger(0, resetAllBtn, OBJPROP_YSIZE, btnHeight);
      ObjectSetString(0, resetAllBtn, OBJPROP_TEXT, "⚡ RESET ALL PROVIDERS");
      ObjectSetInteger(0, resetAllBtn, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, resetAllBtn, OBJPROP_BGCOLOR, clrOrange);
      ObjectSetInteger(0, resetAllBtn, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, resetAllBtn, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, resetAllBtn, OBJPROP_SELECTABLE, false);
   }
   
   // Instructions label
   string instrLabel = "SHRA_Instructions";
   if(ObjectCreate(0, instrLabel, OBJ_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, instrLabel, OBJPROP_XDISTANCE, xPos);
      ObjectSetInteger(0, instrLabel, OBJPROP_YDISTANCE, allBtnY + 40);
      ObjectSetString(0, instrLabel, OBJPROP_TEXT, "Keyboard: R = Reset All, 1-9 = Reset #");
      ObjectSetInteger(0, instrLabel, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, instrLabel, OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, instrLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   }
}

//+------------------------------------------------------------------+
//| UPDATE BUTTON COLORS                                             |
//+------------------------------------------------------------------+
void UpdateButtonColors()
{
   if(!ShowChartButtons) return;
   
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      string btnName = "SHRA_btnReset_" + g_ProviderStats[i].providerId;
      
      if(ObjectFind(0, btnName) >= 0)
      {
         if(g_ProviderStats[i].killSwitchTriggered)
         {
            ObjectSetInteger(0, btnName, OBJPROP_BGCOLOR, ButtonColorBlocked);
            ObjectSetString(0, btnName, OBJPROP_TEXT, "🔴 Reset: " + g_ProviderStats[i].providerId);
            ObjectSetInteger(0, btnName, OBJPROP_COLOR, clrWhite);
         }
         else
         {
            ObjectSetInteger(0, btnName, OBJPROP_BGCOLOR, ButtonColorActive);
            ObjectSetString(0, btnName, OBJPROP_TEXT, "✓ " + g_ProviderStats[i].providerId);
            ObjectSetInteger(0, btnName, OBJPROP_COLOR, clrWhite);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DELETE CHART BUTTONS                                             |
//+------------------------------------------------------------------+
void DeleteChartButtons()
{
   ObjectDelete(0, "SHRA_Title");
   ObjectDelete(0, "SHRA_Instructions");
   ObjectDelete(0, "SHRA_btnResetAll");
   
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      ObjectDelete(0, "SHRA_btnReset_" + g_ProviderStats[i].providerId);
   }
}

//+------------------------------------------------------------------+
//| CHART EVENT HANDLER                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // BUTTON CLICKS
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      // Individual provider reset
      if(StringFind(sparam, "SHRA_btnReset_") == 0)
      {
         string providerId = StringSubstr(sparam, 14);
         
         int response = MessageBox(
            StringFormat("Reset kill switch for:\n\n%s\n\nRe-enable trading?", providerId),
            "Confirm Reset",
            MB_YESNO | MB_ICONQUESTION
         );
         
         if(response == IDYES)
         {
            ResetProviderKillSwitch(providerId);
            UpdateButtonColors();
         }
         
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      
      // Reset ALL button
      if(sparam == "SHRA_btnResetAll")
      {
         int response = MessageBox(
            "Reset kill switches for ALL providers?\n\nThis will re-enable ALL trading.",
            "Confirm Reset ALL",
            MB_YESNO | MB_ICONWARNING
         );
         
         if(response == IDYES)
         {
            int resetCount = 0;
            for(int i = 0; i < ArraySize(g_ProviderStats); i++)
            {
               if(g_ProviderStats[i].killSwitchTriggered)
               {
                  ResetProviderKillSwitch(g_ProviderStats[i].providerId);
                  resetCount++;
               }
            }
            
            UpdateButtonColors();
            Alert(StringFormat("Reset %d provider kill switches", resetCount));
         }
         
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
   }
   
   // KEYBOARD SHORTCUTS
   if(EnableKeyboardShortcuts && id == CHARTEVENT_KEYDOWN)
   {
      // Press 'R' to reset ALL
      if(lparam == 'R' || lparam == 'r')
      {
         int response = MessageBox(
            "Reset ALL provider kill switches?\n\n(Keyboard shortcut: R)",
            "Confirm Reset ALL",
            MB_YESNO | MB_ICONWARNING
         );
         
         if(response == IDYES)
         {
            int resetCount = 0;
            for(int i = 0; i < ArraySize(g_ProviderStats); i++)
            {
               if(g_ProviderStats[i].killSwitchTriggered)
               {
                  ResetProviderKillSwitch(g_ProviderStats[i].providerId);
                  resetCount++;
               }
            }
            
            UpdateButtonColors();
            Alert(StringFormat("Reset %d provider kill switches (R key)", resetCount));
         }
      }
      
      // Press '1', '2', '3', etc. to reset specific provider
      if(lparam >= '1' && lparam <= '9')
      {
         int providerIdx = (int)(lparam - '1');
         
         if(providerIdx < ArraySize(g_ProviderStats))
         {
            string pid = g_ProviderStats[providerIdx].providerId;
            
            if(g_ProviderStats[providerIdx].killSwitchTriggered)
            {
               int response = MessageBox(
                  StringFormat("Reset kill switch for:\n\n%s\n\n(Keyboard shortcut: %d)", 
                              pid, providerIdx + 1),
                  "Confirm Reset",
                  MB_YESNO | MB_ICONQUESTION
               );
               
               if(response == IDYES)
               {
                  ResetProviderKillSwitch(pid);
                  UpdateButtonColors();
                  Alert(StringFormat("Reset provider: %s (key %d)", pid, providerIdx + 1));
               }
            }
            else
            {
               Alert(StringFormat("Provider %s kill switch not active", pid));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== SignalHarvester Provider DD Manager v3.0 ===");
   Print("Features: Peak DD, Chart Buttons, Keyboard Shortcuts, CSV Audit");
   
   g_AuditFileName = "shra_provider_audit_" + IntegerToString(AccountNumber()) + ".csv";
   
   if(!ParseProviderDDSettings())
   {
      Alert("ERROR: No valid providers in ProviderDDSettings!");
      return INIT_FAILED;
   }
   
   LoadPersistedState();
   
   g_LastStateSave = TimeCurrent();
   g_LastClosedPLUpdate = TimeCurrent();
   g_LastButtonUpdate = TimeCurrent();
   
   CreateChartButtons();
   UpdateButtonColors();
   
   AppendToAuditLog("SYSTEM", "EA_START", 0.0, 
                    StringFormat("Initialized with %d providers", ArraySize(g_ProviderStats)));
   
   Print(StringFormat("✓ Initialized %d providers", ArraySize(g_ProviderStats)));
   Print(StringFormat("✓ Chart buttons: %s", ShowChartButtons ? "Enabled" : "Disabled"));
   Print(StringFormat("✓ Keyboard shortcuts: %s", EnableKeyboardShortcuts ? "Enabled" : "Disabled"));
   Print(StringFormat("✓ Audit log: %s", g_AuditFileName));
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== SignalHarvester Provider DD Manager Stopping ===");
   
   SavePersistedState();
   DeleteChartButtons();
   
   AppendToAuditLog("SYSTEM", "EA_STOP", 0.0, StringFormat("Reason: %d", reason));
   
   Print(StringFormat("EA stopped, reason: %d", reason));
}

//+------------------------------------------------------------------+
//| EXPERT TICK FUNCTION                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ScanOpenOrders();
   UpdateProviderEquityStats();
   CheckProviderFloatingDD();
   
   if(TimeCurrent() - g_LastButtonUpdate >= 5)
   {
      UpdateButtonColors();
      g_LastButtonUpdate = TimeCurrent();
   }
   
   if(TimeCurrent() - g_LastStateSave >= StateSaveIntervalSeconds)
   {
      SavePersistedState();
      g_LastStateSave = TimeCurrent();
   }
}
//+------------------------------------------------------------------+