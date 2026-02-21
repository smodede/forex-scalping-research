//+------------------------------------------------------------------+
//|                  SignalHarvesterProviderDD_Complete.mq4          |
//|         Per-Provider + Group DD + All Reset Methods Integrated   |
//|                    PRODUCTION READY v3.2                         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "3.2"
#property strict

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - FTMO $200K ACCOUNT CONFIGURATION              |
//+------------------------------------------------------------------+
input string ProviderDDSettings = "sig_284538,12.0,18.0,22.0,20.0;sig_284214,12.0,18.0,22.0,20.0;sig_284720,12.0,18.0,22.0,20.0;sig_286254,12.0,18.0,22.0,20.0;sig_286289,12.0,18.0,22.0,20.0;sig_276594,12.0,18.0,22.0,20.0";
// Format: ProviderID,warnDD%,critDD%,emergDD%,minPeak;...
// Sets default DD thresholds for ALL providers in Group 284538
// Accommodates signals up to 20% Historical DD
// 12% = Early warning, 18% = Damage control, 22% = Hard stop (exceeded historical)
// minPeak = Minimum closed P/L before DD tracking starts (e.g., 20.0 = $20)
// NOTE: EA auto-detects ALL signals starting with "sig_" and groups by suffix
//
// GROUP TRACKING: All providers ending in _284538 are automatically grouped:
//   sig_56663716_284538, sig_56663050_284538, sig_56664448_284538, etc.
//   → All part of Group 284538 with shared thresholds
// Group DD triggers if COMBINED performance exceeds group thresholds

// Group-Level Protection (tracks combined stats for all providers in same group)
input bool   EnableGroupLevelProtection = true;  // Enable group DD tracking (e.g., all sig_*_284538)
input double GroupWarnDDPercent = 15.0;          // Warning threshold for combined group DD
input double GroupCritDDPercent = 22.0;          // Critical threshold - trim worst providers
input double GroupEmergDDPercent = 28.0;         // Emergency - kill all providers in group
input double MaxGroupLossAmount = 5000.0;        // $5,000 max loss per group (2.5% of $200K)
input double MaxGroupLossPercent = 3.0;          // 3% max loss per group

// Absolute Loss Protection - FTMO SAFETY (10% total account DD limit!)
input double MaxProviderLossAmount = 2500.0;     // $2,500 per provider (1.25% of $200K)
input double MaxProviderLossPercent = 1.5;       // 1.5% max loss per provider (FTMO-appropriate)
input bool   EnableAbsoluteLossProtection = true; // CRITICAL: Protects against bad signals
input int    StateSaveIntervalSeconds = 300;
input int    RecalcClosedPLIntervalSec = 600;
input bool   EnableDebugLogs = true;
input bool   ShowChartButtons = true;           // Show reset buttons on chart
input bool   EnableKeyboardShortcuts = true;    // Enable keyboard shortcuts

// Auto-Reset Settings
input bool   EnableAutoResetAfterKillSwitch = true;  // Auto-reset kill switches after trigger
input int    AutoResetDelaySeconds = 300;             // Delay before auto-reset (5 minutes default)

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
   string   groupId;              // Group ID extracted from provider (e.g., "284538")
   double   peakEquity;
   double   currentEquity;
   double   closedPL;
   double   floatingPL;
   double   warnDDPercent;
   double   critDDPercent;
   double   emergDDPercent;
   double   minPeakThreshold;     // Minimum peak before DD tracking starts
   bool     killSwitchTriggered;
   datetime lastWarnTime;
   datetime killSwitchTime;       // When kill switch was triggered
   int      tradesCount;
};

struct GroupStats
{
   string   groupId;
   double   peakEquity;
   double   currentEquity;
   double   closedPL;
   double   floatingPL;
   int      totalProviders;
   int      activeProviders;      // Providers with open trades
   int      totalTrades;
   bool     killSwitchTriggered;
   datetime killSwitchTime;       // When kill switch was triggered
   datetime lastWarnTime;
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
GroupStats    g_GroupStats[];
TradeInfo     g_OpenTrades[];
datetime      g_LastStateSave = 0;
datetime      g_LastClosedPLUpdate = 0;
datetime      g_LastButtonUpdate = 0;
datetime      g_LastStatusLog = 0;
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
//| Extract Group ID from Provider ID                                |
//+------------------------------------------------------------------+
string ExtractGroupId(string providerId)
{
   // Extract group ID from format: sig_XXXXXXXX_GROUPID
   int lastUnderscore = StringFind(providerId, "_", StringFind(providerId, "_") + 1);
   
   if(lastUnderscore > 0 && lastUnderscore < StringLen(providerId) - 1)
   {
      string groupId = StringSubstr(providerId, lastUnderscore + 1);
      return groupId;
   }
   
   return ""; // No group ID found
}

//+------------------------------------------------------------------+
//| Find Group Stats Index                                           |
//+------------------------------------------------------------------+
int FindGroupStatsIndex(string groupId)
{
   for(int i = 0; i < ArraySize(g_GroupStats); i++)
   {
      if(g_GroupStats[i].groupId == groupId)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Ensure Group Exists                                              |
//+------------------------------------------------------------------+
int EnsureGroupExists(string groupId)
{
   if(StringLen(groupId) == 0) return -1;
   
   int idx = FindGroupStatsIndex(groupId);
   if(idx >= 0) return idx;
   
   int size = ArraySize(g_GroupStats);
   ArrayResize(g_GroupStats, size + 1);
   
   g_GroupStats[size].groupId = groupId;
   g_GroupStats[size].peakEquity = 0.0;
   g_GroupStats[size].currentEquity = 0.0;
   g_GroupStats[size].closedPL = 0.0;
   g_GroupStats[size].floatingPL = 0.0;
   g_GroupStats[size].totalProviders = 0;
   g_GroupStats[size].activeProviders = 0;
   g_GroupStats[size].totalTrades = 0;
   g_GroupStats[size].killSwitchTriggered = false;
   g_GroupStats[size].killSwitchTime = 0;
   g_GroupStats[size].lastWarnTime = 0;
   
   DebugLog(StringFormat("Created group tracker: %s", groupId));
   return size;
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
      
      if(numParts == 4 || numParts == 5)
      {
         string pid = parts[0];
         double warn = StringToDouble(parts[1]);
         double crit = StringToDouble(parts[2]);
         double emerg = StringToDouble(parts[3]);
         double minPeak = (numParts == 5) ? StringToDouble(parts[4]) : 0.0;
         
         if(warn > 0 && crit > warn && emerg > crit)
         {
            ArrayResize(g_ProviderStats, providerCount + 1);
            
            g_ProviderStats[providerCount].providerId = pid;
            g_ProviderStats[providerCount].groupId = ExtractGroupId(pid);
            g_ProviderStats[providerCount].warnDDPercent = warn;
            g_ProviderStats[providerCount].critDDPercent = crit;
            g_ProviderStats[providerCount].emergDDPercent = emerg;
            g_ProviderStats[providerCount].minPeakThreshold = minPeak;
            g_ProviderStats[providerCount].peakEquity = 0.0;
            g_ProviderStats[providerCount].currentEquity = 0.0;
            g_ProviderStats[providerCount].closedPL = 0.0;
            g_ProviderStats[providerCount].floatingPL = 0.0;
            g_ProviderStats[providerCount].killSwitchTriggered = false;
            g_ProviderStats[providerCount].killSwitchTime = 0;
            g_ProviderStats[providerCount].lastWarnTime = 0;
            g_ProviderStats[providerCount].tradesCount = 0;
            
            // Ensure group exists
            if(StringLen(g_ProviderStats[providerCount].groupId) > 0)
               EnsureGroupExists(g_ProviderStats[providerCount].groupId);
            
            providerCount++;
            
            DebugLog(StringFormat("Parsed provider: %s (Warn:%.1f%%, Crit:%.1f%%, Emerg:%.1f%%, MinPeak:$%.2f)",
                    pid, warn, crit, emerg, minPeak));
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
   g_ProviderStats[size].groupId = ExtractGroupId(providerId);
   
   // Use default thresholds from first configured provider (or hardcoded defaults)
   if(ArraySize(g_ProviderStats) > 1)
   {
      g_ProviderStats[size].warnDDPercent = g_ProviderStats[0].warnDDPercent;
      g_ProviderStats[size].critDDPercent = g_ProviderStats[0].critDDPercent;
      g_ProviderStats[size].emergDDPercent = g_ProviderStats[0].emergDDPercent;
      g_ProviderStats[size].minPeakThreshold = g_ProviderStats[0].minPeakThreshold;
   }
   else
   {
      g_ProviderStats[size].warnDDPercent = 12.0;
      g_ProviderStats[size].critDDPercent = 18.0;
      g_ProviderStats[size].emergDDPercent = 22.0;
      g_ProviderStats[size].minPeakThreshold = 0.0;
   }
   
   g_ProviderStats[size].peakEquity = 0.0;
   g_ProviderStats[size].currentEquity = 0.0;
   g_ProviderStats[size].closedPL = 0.0;
   g_ProviderStats[size].floatingPL = 0.0;
   g_ProviderStats[size].killSwitchTriggered = false;
   g_ProviderStats[size].killSwitchTime = 0;
   g_ProviderStats[size].killSwitchTime = 0;
   g_ProviderStats[size].lastWarnTime = 0;
   g_ProviderStats[size].tradesCount = 0;
   
   // Ensure group exists
   if(StringLen(g_ProviderStats[size].groupId) > 0)
      EnsureGroupExists(g_ProviderStats[size].groupId);
   
   DebugLog(StringFormat("Auto-added provider: %s (DD thresholds: %.1f%%, %.1f%%, %.1f%%)", 
                        providerId,
                        g_ProviderStats[size].warnDDPercent,
                        g_ProviderStats[size].critDDPercent,
                        g_ProviderStats[size].emergDDPercent));
   return size;
}

//+------------------------------------------------------------------+
//| Identify Provider from Trade                                     |
//+------------------------------------------------------------------+
string IdentifyProvider(int magic, string comment)
{
   // First check configured providers for exact matches
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      if(StringFind(comment, g_ProviderStats[i].providerId) >= 0)
         return g_ProviderStats[i].providerId;
   }
   
   // Auto-detect any provider starting with "sig_"
   int sigPos = StringFind(comment, "sig_");
   if(sigPos >= 0)
   {
      // Extract provider ID: sig_XXXXXXXX_YYYYYY format
      string extracted = "";
      int startPos = sigPos;
      
      // Find the end of the provider ID (until space, comma, or end of string)
      for(int i = startPos; i < StringLen(comment); i++)
      {
         string ch = StringSubstr(comment, i, 1);
         
         // Provider ID contains: sig_ + numbers + underscores
         if((ch >= "0" && ch <= "9") || ch == "_" || (ch >= "a" && ch <= "z"))
         {
            extracted += ch;
         }
         else
         {
            break; // Stop at first non-matching character
         }
      }
      
      // Return the extracted provider ID if valid format (sig_XXXXXX_XXXXXX)
      if(StringLen(extracted) > 4) // More than just "sig_"
      {
         DebugLog(StringFormat("Auto-detected provider: %s from comment: %s", extracted, comment));
         return extracted;
      }
   }
   
   // Return empty string if no matching provider found
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
      
      DebugLog(StringFormat("✓ Matched trade #%d to provider: %s", OrderTicket(), providerId));
      
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
      // BUG FIX: Use temporary array to avoid false DD spikes during recalculation
      // Previous bug: Reset closedPL to 0 first, creating timing window where
      // DD calculations saw $0 closed P/L and triggered false kill switches
      double tempClosedPL[];
      ArrayResize(tempClosedPL, ArraySize(g_ProviderStats));
      ArrayInitialize(tempClosedPL, 0.0);
      
      for(int i = 0; i < OrdersHistoryTotal(); i++)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
         if(OrderType() > OP_SELL) continue;
         
         string pid = IdentifyProvider(OrderMagicNumber(), OrderComment());
         
         // Skip closed trades without valid provider identification
         if(StringLen(pid) == 0) continue;
         
         int idx = EnsureProviderExists(pid);
         
         tempClosedPL[idx] += OrderProfit() + OrderSwap() + OrderCommission();
      }
      
      // Atomic update: All providers updated simultaneously (no timing window)
      for(int i = 0; i < ArraySize(g_ProviderStats); i++)
         g_ProviderStats[i].closedPL = tempClosedPL[i];
      
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
   
   // Update group-level statistics
   UpdateGroupStats();
}

//+------------------------------------------------------------------+
//| Update Group Statistics                                           |
//+------------------------------------------------------------------+
void UpdateGroupStats()
{
   if(!EnableGroupLevelProtection) return;
   
   // Reset all group stats
   for(int i = 0; i < ArraySize(g_GroupStats); i++)
   {
      g_GroupStats[i].closedPL = 0.0;
      g_GroupStats[i].floatingPL = 0.0;
      g_GroupStats[i].totalProviders = 0;
      g_GroupStats[i].activeProviders = 0;
      g_GroupStats[i].totalTrades = 0;
   }
   
   // Aggregate provider stats into groups (exclude killed providers)
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      string groupId = g_ProviderStats[i].groupId;
      if(StringLen(groupId) == 0) continue;
      
      // Skip providers with active kill switches - they're "dead" and shouldn't
      // influence group risk decisions. This prevents cascading group kills when
      // a profitable provider's kill switch triggers and removes its cushion.
      if(g_ProviderStats[i].killSwitchTriggered) continue;
      
      int gIdx = EnsureGroupExists(groupId);
      if(gIdx < 0) continue;
      
      g_GroupStats[gIdx].closedPL += g_ProviderStats[i].closedPL;
      g_GroupStats[gIdx].floatingPL += g_ProviderStats[i].floatingPL;
      g_GroupStats[gIdx].totalProviders++;
      
      if(g_ProviderStats[i].tradesCount > 0)
      {
         g_GroupStats[gIdx].activeProviders++;
         g_GroupStats[gIdx].totalTrades += g_ProviderStats[i].tradesCount;
      }
   }
   
   // Calculate current equity and update peaks
   for(int i = 0; i < ArraySize(g_GroupStats); i++)
   {
      g_GroupStats[i].currentEquity = g_GroupStats[i].closedPL + g_GroupStats[i].floatingPL;
      
      // Update peak based on closed P/L
      if(g_GroupStats[i].closedPL > g_GroupStats[i].peakEquity)
         g_GroupStats[i].peakEquity = g_GroupStats[i].closedPL;
   }
}

//+------------------------------------------------------------------+
//| Log Provider Status (Diagnostic)                                 |
//+------------------------------------------------------------------+
void LogProviderStatus()
{
   Print("\n========== PROVIDER STATUS REPORT ==========");
   Print(StringFormat("Configured Providers: %d", ArraySize(g_ProviderStats)));
   Print(StringFormat("Tracked Groups: %d", ArraySize(g_GroupStats)));
   Print(StringFormat("Open Trades Tracked: %d", ArraySize(g_OpenTrades)));
   
   // Log group statistics first
   if(EnableGroupLevelProtection && ArraySize(g_GroupStats) > 0)
   {
      Print("\n--- GROUP STATISTICS ---");
      for(int i = 0; i < ArraySize(g_GroupStats); i++)
      {
         double groupDD = 0.0;
         if(g_GroupStats[i].peakEquity > 0)
            groupDD = ((g_GroupStats[i].peakEquity - g_GroupStats[i].currentEquity) / g_GroupStats[i].peakEquity) * 100.0;
         
         Print(StringFormat("\n[GROUP %s]", g_GroupStats[i].groupId));
         Print(StringFormat("  Providers: %d (%d active) | Trades: %d",
                           g_GroupStats[i].totalProviders,
                           g_GroupStats[i].activeProviders,
                           g_GroupStats[i].totalTrades));
         Print(StringFormat("  Peak: $%.2f | Current: $%.2f | DD: %.2f%%",
                           g_GroupStats[i].peakEquity,
                           g_GroupStats[i].currentEquity,
                           groupDD));
         Print(StringFormat("  Closed P/L: $%.2f | Floating P/L: $%.2f",
                           g_GroupStats[i].closedPL,
                           g_GroupStats[i].floatingPL));
         Print(StringFormat("  Kill Switch: %s",
                           g_GroupStats[i].killSwitchTriggered ? "ACTIVE" : "Off"));
      }
   }
   
   Print("\n--- INDIVIDUAL PROVIDERS ---");
   
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      double dd = 0.0;
      if(g_ProviderStats[i].peakEquity > 0)
         dd = ((g_ProviderStats[i].peakEquity - g_ProviderStats[i].currentEquity) / g_ProviderStats[i].peakEquity) * 100.0;
      
      Print(StringFormat("\n[%s] (Group: %s)", g_ProviderStats[i].providerId, g_ProviderStats[i].groupId));
      Print(StringFormat("  Peak: $%.2f | Current: $%.2f | DD: %.2f%%", 
                        g_ProviderStats[i].peakEquity, 
                        g_ProviderStats[i].currentEquity, 
                        dd));
      Print(StringFormat("  Closed P/L: $%.2f | Floating P/L: $%.2f", 
                        g_ProviderStats[i].closedPL, 
                        g_ProviderStats[i].floatingPL));
      Print(StringFormat("  Open Trades: %d | Kill Switch: %s", 
                        g_ProviderStats[i].tradesCount,
                        g_ProviderStats[i].killSwitchTriggered ? "ACTIVE" : "Off"));
      
      AppendToAuditLog(g_ProviderStats[i].providerId, "STATUS", dd, 
                      StringFormat("Peak:%.2f Curr:%.2f Trades:%d", 
                                  g_ProviderStats[i].peakEquity, 
                                  g_ProviderStats[i].currentEquity,
                                  g_ProviderStats[i].tradesCount));
   }
   Print("==========================================\n");
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
//| Auto-Reset Kill Switches                                         |
//+------------------------------------------------------------------+
void AutoResetKillSwitches()
{
   if(!EnableAutoResetAfterKillSwitch) return;
   
   datetime currentTime = TimeCurrent();
   
   // Auto-reset provider kill switches
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      if(g_ProviderStats[i].killSwitchTriggered && 
         g_ProviderStats[i].killSwitchTime > 0 &&
         g_ProviderStats[i].tradesCount == 0)  // Only reset if no open trades
      {
         if(currentTime - g_ProviderStats[i].killSwitchTime >= AutoResetDelaySeconds)
         {
            g_ProviderStats[i].killSwitchTriggered = false;
            g_ProviderStats[i].peakEquity = 0.0;  // Reset peak to allow fresh start
            g_ProviderStats[i].closedPL = 0.0;
            
            DebugLog(StringFormat("✅ Auto-reset kill switch for provider: %s", 
                                 g_ProviderStats[i].providerId));
            
            AppendToAuditLog(g_ProviderStats[i].providerId, "AUTO_RESET", 0.0,
                           StringFormat("Kill switch auto-reset after %d seconds", AutoResetDelaySeconds));
            
            // Update button colors
            UpdateButtonColors();
         }
      }
   }
   
   // Auto-reset group kill switches
   for(int i = 0; i < ArraySize(g_GroupStats); i++)
   {
      if(g_GroupStats[i].killSwitchTriggered && 
         g_GroupStats[i].killSwitchTime > 0 &&
         g_GroupStats[i].totalTrades == 0)  // Only reset if no open trades in group
      {
         if(currentTime - g_GroupStats[i].killSwitchTime >= AutoResetDelaySeconds)
         {
            g_GroupStats[i].killSwitchTriggered = false;
            g_GroupStats[i].peakEquity = 0.0;  // Reset peak to allow fresh start
            g_GroupStats[i].closedPL = 0.0;
            
            DebugLog(StringFormat("✅ Auto-reset kill switch for group: %s", 
                                 g_GroupStats[i].groupId));
            
            AppendToAuditLog("GROUP_" + g_GroupStats[i].groupId, "AUTO_RESET", 0.0,
                           StringFormat("Group kill switch auto-reset after %d seconds", AutoResetDelaySeconds));
            
            // Update button colors
            UpdateGroupButtonColors();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check Group Floating DD                                          |
//+------------------------------------------------------------------+
void CheckGroupFloatingDD()
{
   if(!EnableGroupLevelProtection) return;
   
   for(int i = 0; i < ArraySize(g_GroupStats); i++)
   {
      string groupId = g_GroupStats[i].groupId;
      
      if(g_GroupStats[i].killSwitchTriggered) continue;
      
      double peak = g_GroupStats[i].peakEquity;
      double current = g_GroupStats[i].currentEquity;
      
      // ═══════════════════════════════════════════════════════════════
      // GROUP ABSOLUTE LOSS PROTECTION
      // ═══════════════════════════════════════════════════════════════
      if(current < 0)
      {
         bool triggerAbsoluteLoss = false;
         string lossReason = "";
         
         if(current <= -MaxGroupLossAmount)
         {
            triggerAbsoluteLoss = true;
            lossReason = StringFormat("Lost $%.2f (limit: $%.2f)", -current, MaxGroupLossAmount);
         }
         
         double accountEquity = AccountEquity();
         if(accountEquity > 0)
         {
            double lossPercent = (-current / accountEquity) * 100.0;
            if(lossPercent >= MaxGroupLossPercent)
            {
               triggerAbsoluteLoss = true;
               lossReason = StringFormat("Lost %.2f%% of account (limit: %.2f%%)",
                                        lossPercent, MaxGroupLossPercent);
            }
         }
         
         if(triggerAbsoluteLoss)
         {
            Print(StringFormat("🚨 GROUP ABSOLUTE LOSS: Group %s - %s - KILL ALL!",
                              groupId, lossReason));
            
            int closedCount = CloseAllGroupTrades(groupId, "Group absolute loss");
            g_GroupStats[i].killSwitchTriggered = true;
            g_GroupStats[i].killSwitchTime = TimeCurrent();
            
            // Trigger kill switch for all providers in group
            for(int j = 0; j < ArraySize(g_ProviderStats); j++)
            {
               if(g_ProviderStats[j].groupId == groupId)
               {
                  g_ProviderStats[j].killSwitchTriggered = true;
                  g_ProviderStats[j].killSwitchTime = TimeCurrent();
               }
            }
            
            AppendToAuditLog("GROUP_" + groupId, "GROUP_ABSOLUTE_LOSS", 0.0,
                            StringFormat("%s - Closed %d trades", lossReason, closedCount));
            
            Alert(StringFormat("Group %s: KILL SWITCH - %s!", groupId, lossReason));
            
            // Update button colors immediately
            UpdateButtonColors();
            UpdateGroupButtonColors();
            continue;
         }
      }
      
      // ═══════════════════════════════════════════════════════════════
      // GROUP PEAK-BASED DD PROTECTION
      // ═══════════════════════════════════════════════════════════════
      // Check minimum peak threshold (calculated from provider minPeaks in group)
      double groupMinPeak = 0.0;
      for(int p = 0; p < ArraySize(g_ProviderStats); p++)
      {
         if(g_ProviderStats[p].groupId == groupId && g_ProviderStats[p].minPeakThreshold > groupMinPeak)
            groupMinPeak = g_ProviderStats[p].minPeakThreshold;
      }
      
      if(peak <= 0 || peak < groupMinPeak) continue;
      
      double dd = ((peak - current) / peak) * 100.0;
      if(dd <= 0) continue;
      
      // EMERGENCY
      if(dd >= GroupEmergDDPercent)
      {
         Print(StringFormat("🚨 GROUP EMERGENCY: Group %s DD %.2f%% - KILL ALL!", groupId, dd));
         
         int closedCount = CloseAllGroupTrades(groupId, "Group emergency DD");
         g_GroupStats[i].killSwitchTriggered = true;
         g_GroupStats[i].killSwitchTime = TimeCurrent();
         
         // Trigger kill switch for all providers in group
         for(int j = 0; j < ArraySize(g_ProviderStats); j++)
         {
            if(g_ProviderStats[j].groupId == groupId)
            {
               g_ProviderStats[j].killSwitchTriggered = true;
               g_ProviderStats[j].killSwitchTime = TimeCurrent();
            }
         }
         
         AppendToAuditLog("GROUP_" + groupId, "GROUP_EMERGENCY", dd,
                         StringFormat("Closed %d trades, group kill switch engaged", closedCount));
         
         Alert(StringFormat("Group %s: KILL SWITCH at %.2f%% DD!", groupId, dd));
         
         // Update button colors immediately
         UpdateButtonColors();
         UpdateGroupButtonColors();
         continue;
      }
      
      // CRITICAL
      if(dd >= GroupCritDDPercent)
      {
         Print(StringFormat("🔴 GROUP CRITICAL: Group %s DD %.2f%% - Trimming worst providers!", groupId, dd));
         
         int closedCount = CloseWorstGroupProviders(groupId, 0.3);
         
         AppendToAuditLog("GROUP_" + groupId, "GROUP_CRITICAL", dd,
                         StringFormat("Trimmed worst providers, closed %d trades", closedCount));
         continue;
      }
      
      // WARNING
      if(dd >= GroupWarnDDPercent)
      {
         if(TimeCurrent() - g_GroupStats[i].lastWarnTime >= 300)
         {
            Print(StringFormat("⚠️ GROUP WARNING: Group %s DD %.2f%%", groupId, dd));
            AppendToAuditLog("GROUP_" + groupId, "GROUP_WARNING", dd,
                            StringFormat("%d providers, %d trades",
                                        g_GroupStats[i].totalProviders,
                                        g_GroupStats[i].totalTrades));
            g_GroupStats[i].lastWarnTime = TimeCurrent();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check Provider Floating DD                                       |
//+------------------------------------------------------------------+
void CheckProviderFloatingDD()
{
   // Check group-level DD first
   CheckGroupFloatingDD();
   
   // Then check individual providers
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
            g_ProviderStats[i].killSwitchTime = TimeCurrent();
            
            AppendToAuditLog(pid, "ABSOLUTE_LOSS_KILLSWITCH", 0.0,
                            StringFormat("%s - Closed %d trades", lossReason, closedCount));
            
            Alert(StringFormat("Provider %s: KILL SWITCH - %s!", pid, lossReason));
            
            // Update button colors immediately
            UpdateButtonColors();
            UpdateGroupButtonColors();
            continue;
         }
      }
      
      // ═══════════════════════════════════════════════════════════════
      // PEAK-BASED DD PROTECTION (for providers with profit history)
      // ═══════════════════════════════════════════════════════════════
      if(peak <= 0) continue;  // Skip peak DD if provider never profitable
      
      // Check minimum peak threshold before calculating DD
      if(peak < g_ProviderStats[i].minPeakThreshold)
      {
         if(TimeCurrent() - g_ProviderStats[i].lastWarnTime >= 600)
         {
            DebugLog(StringFormat("Provider %s: Peak $%.2f below threshold $%.2f - DD tracking disabled",
                                 pid, peak, g_ProviderStats[i].minPeakThreshold));
            g_ProviderStats[i].lastWarnTime = TimeCurrent();
         }
         continue;
      }
      
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
         g_ProviderStats[i].killSwitchTime = TimeCurrent();
         
         AppendToAuditLog(pid, "EMERGENCY_KILLSWITCH", dd,
                         StringFormat("Closed %d trades, kill switch engaged", closedCount));
         
         Alert(StringFormat("Provider %s: KILL SWITCH at %.2f%% DD!", pid, dd));
         
         // Update button colors immediately
         UpdateButtonColors();
         UpdateGroupButtonColors();
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
//| Close All Group Trades                                           |
//+------------------------------------------------------------------+
int CloseAllGroupTrades(string groupId, string reason)
{
   int closedCount = 0;
   
   for(int i = ArraySize(g_OpenTrades) - 1; i >= 0; i--)
   {
      string pid = g_OpenTrades[i].providerId;
      int pIdx = FindProviderStatsIndex(pid);
      
      if(pIdx >= 0 && g_ProviderStats[pIdx].groupId == groupId)
      {
         if(CloseOrder(g_OpenTrades[i].ticket, reason))
            closedCount++;
      }
   }
   
   return closedCount;
}

//+------------------------------------------------------------------+
//| Close Worst Group Providers                                      |
//+------------------------------------------------------------------+
int CloseWorstGroupProviders(string groupId, double percent)
{
   // Find all providers in this group and calculate their performance
   int providerIndices[];
   double providerPL[];
   int count = 0;
   
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      if(g_ProviderStats[i].groupId == groupId && g_ProviderStats[i].tradesCount > 0)
      {
         ArrayResize(providerIndices, count + 1);
         ArrayResize(providerPL, count + 1);
         providerIndices[count] = i;
         providerPL[count] = g_ProviderStats[i].floatingPL;
         count++;
      }
   }
   
   if(count == 0) return 0;
   
   // Sort by floating P/L (worst first)
   for(int i = 0; i < count - 1; i++)
   {
      for(int j = 0; j < count - i - 1; j++)
      {
         if(providerPL[j] > providerPL[j+1])
         {
            int tempIdx = providerIndices[j];
            providerIndices[j] = providerIndices[j+1];
            providerIndices[j+1] = tempIdx;
            
            double tempPL = providerPL[j];
            providerPL[j] = providerPL[j+1];
            providerPL[j+1] = tempPL;
         }
      }
   }
   
   // Close all trades from worst performing providers
   int providersToClose = (int)MathMax(1, MathCeil(count * percent));
   int totalClosed = 0;
   
   for(int i = 0; i < providersToClose && i < count; i++)
   {
      int pIdx = providerIndices[i];
      string pid = g_ProviderStats[pIdx].providerId;
      
      for(int j = ArraySize(g_OpenTrades) - 1; j >= 0; j--)
      {
         if(g_OpenTrades[j].providerId == pid)
         {
            if(CloseOrder(g_OpenTrades[j].ticket, "Group DD - worst provider trim"))
               totalClosed++;
         }
      }
      
      DebugLog(StringFormat("Trimmed provider %s from group %s (PL: %.2f)",
                           pid, groupId, providerPL[i]));
   }
   
   return totalClosed;
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
//| Reset Group Kill Switch                                          |
//+------------------------------------------------------------------+
void ResetGroupKillSwitch(string groupId)
{
   int gIdx = FindGroupStatsIndex(groupId);
   
   if(gIdx < 0)
   {
      DebugLog(StringFormat("Group %s not found", groupId));
      return;
   }
   
   double oldPeak = g_GroupStats[gIdx].peakEquity;
   double currentEquity = g_GroupStats[gIdx].currentEquity;
   
   // Reset group peak
   g_GroupStats[gIdx].peakEquity = currentEquity;
   g_GroupStats[gIdx].killSwitchTriggered = false;
   
   // Reset all provider kill switches in this group
   int resetCount = 0;
   for(int i = 0; i < ArraySize(g_ProviderStats); i++)
   {
      if(g_ProviderStats[i].groupId == groupId)
      {
         g_ProviderStats[i].peakEquity = g_ProviderStats[i].currentEquity;
         g_ProviderStats[i].killSwitchTriggered = false;
         resetCount++;
      }
   }
   
   AppendToAuditLog("GROUP_" + groupId, "GROUP_RESET", 0.0,
                   StringFormat("Group reset - Peak: %.2f → %.2f, %d providers reset",
                               oldPeak, currentEquity, resetCount));
   
   Alert(StringFormat("Group %s: RESET - %d providers (Peak: $%.2f → $%.2f)",
                     groupId, resetCount, oldPeak, currentEquity));
   DebugLog(StringFormat("Group %s reset: %d providers", groupId, resetCount));
   
   // Save state immediately so global variables update
   SavePersistedState();
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
   
   // Save state immediately so global variables update
   SavePersistedState();
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
   
   // Save group stats
   for(int i = 0; i < ArraySize(g_GroupStats); i++)
   {
      string prefix = "SHRA_" + IntegerToString(AccountNumber()) + "_GROUP_" + 
                      g_GroupStats[i].groupId + "_";
      
      GlobalVariableSet(prefix + "PeakEquity", g_GroupStats[i].peakEquity);
      GlobalVariableSet(prefix + "KillSwitch", g_GroupStats[i].killSwitchTriggered ? 1.0 : 0.0);
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
   
   // Load group stats
   for(int i = 0; i < ArraySize(g_GroupStats); i++)
   {
      string prefix = "SHRA_" + IntegerToString(AccountNumber()) + "_GROUP_" + 
                      g_GroupStats[i].groupId + "_";
      
      if(GlobalVariableCheck(prefix + "PeakEquity"))
      {
         g_GroupStats[i].peakEquity = GlobalVariableGet(prefix + "PeakEquity");
      }
      
      if(GlobalVariableCheck(prefix + "KillSwitch"))
      {
         g_GroupStats[i].killSwitchTriggered = (GlobalVariableGet(prefix + "KillSwitch") > 0);
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
   
   // Group reset buttons (if group-level protection enabled)
   int groupBtnY = yPos + (ArraySize(g_ProviderStats) * spacing) + 10;
   
   if(EnableGroupLevelProtection && ArraySize(g_GroupStats) > 0)
   {
      for(int i = 0; i < ArraySize(g_GroupStats); i++)
      {
         string groupBtnName = "SHRA_btnResetGroup_" + g_GroupStats[i].groupId;
         
         if(ObjectCreate(0, groupBtnName, OBJ_BUTTON, 0, 0, 0))
         {
            ObjectSetInteger(0, groupBtnName, OBJPROP_XDISTANCE, xPos);
            ObjectSetInteger(0, groupBtnName, OBJPROP_YDISTANCE, groupBtnY + (i * spacing));
            ObjectSetInteger(0, groupBtnName, OBJPROP_XSIZE, btnWidth);
            ObjectSetInteger(0, groupBtnName, OBJPROP_YSIZE, btnHeight);
            ObjectSetString(0, groupBtnName, OBJPROP_TEXT, "🔄 Reset Group " + g_GroupStats[i].groupId);
            ObjectSetInteger(0, groupBtnName, OBJPROP_FONTSIZE, 9);
            ObjectSetInteger(0, groupBtnName, OBJPROP_BGCOLOR, clrDarkBlue);
            ObjectSetInteger(0, groupBtnName, OBJPROP_COLOR, clrWhite);
            ObjectSetInteger(0, groupBtnName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, groupBtnName, OBJPROP_SELECTABLE, false);
         }
      }
      
      groupBtnY += ArraySize(g_GroupStats) * spacing + 5;
   }
   
   // Reset ALL button
   string resetAllBtn = "SHRA_btnResetAll";
   int allBtnY = groupBtnY;
   
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
      ObjectSetString(0, instrLabel, OBJPROP_TEXT, "Keyboard: R = Reset All, G = Reset Group, 1-9 = Reset #");
      ObjectSetInteger(0, instrLabel, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, instrLabel, OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, instrLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   }
}

//+------------------------------------------------------------------+
//| UPDATE GROUP BUTTON COLORS                                       |
//+------------------------------------------------------------------+
void UpdateGroupButtonColors()
{
   if(!ShowChartButtons || !EnableGroupLevelProtection) return;
   
   for(int i = 0; i < ArraySize(g_GroupStats); i++)
   {
      string btnName = "SHRA_btnResetGroup_" + g_GroupStats[i].groupId;
      
      if(ObjectFind(0, btnName) >= 0)
      {
         double groupDD = 0.0;
         if(g_GroupStats[i].peakEquity > 0)
            groupDD = ((g_GroupStats[i].peakEquity - g_GroupStats[i].currentEquity) / g_GroupStats[i].peakEquity) * 100.0;
         
         string label = StringFormat("🔄 Reset Group %s (DD:%.1f%%)",
                                     g_GroupStats[i].groupId, groupDD);
         
         color btnColor = clrDarkBlue;
         if(g_GroupStats[i].killSwitchTriggered)
            btnColor = ButtonColorBlocked;
         else if(groupDD >= GroupCritDDPercent)
            btnColor = clrCrimson;
         else if(groupDD >= GroupWarnDDPercent)
            btnColor = clrOrange;
         
         ObjectSetString(0, btnName, OBJPROP_TEXT, label);
         ObjectSetInteger(0, btnName, OBJPROP_BGCOLOR, btnColor);
      }
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
   
   for(int i = 0; i < ArraySize(g_GroupStats); i++)
   {
      ObjectDelete(0, "SHRA_btnResetGroup_" + g_GroupStats[i].groupId);
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
      // Group reset button
      if(StringFind(sparam, "SHRA_btnResetGroup_") == 0)
      {
         string groupId = StringSubstr(sparam, 19);
         
         int gIdx = FindGroupStatsIndex(groupId);
         if(gIdx >= 0)
         {
            int response = MessageBox(
               StringFormat("Reset kill switch for GROUP:\n\n%s\n\n(%d providers)\n\nRe-enable trading?",
                           groupId, g_GroupStats[gIdx].totalProviders),
               "Confirm Group Reset",
               MB_YESNO | MB_ICONQUESTION
            );
            
            if(response == IDYES)
            {
               ResetGroupKillSwitch(groupId);
               UpdateButtonColors();
               UpdateGroupButtonColors();
            }
         }
         
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      
      // Individual provider reset
      if(StringFind(sparam, "SHRA_btnReset_") == 0 && StringFind(sparam, "Group") < 0)
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
            UpdateGroupButtonColors();
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
            
            // Also reset all groups
            for(int i = 0; i < ArraySize(g_GroupStats); i++)
            {
               if(g_GroupStats[i].killSwitchTriggered)
               {
                  g_GroupStats[i].killSwitchTriggered = false;
                  g_GroupStats[i].peakEquity = g_GroupStats[i].currentEquity;
               }
            }
            
            UpdateButtonColors();
            UpdateGroupButtonColors();
            SavePersistedState();
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
            
            // Also reset all groups
            for(int i = 0; i < ArraySize(g_GroupStats); i++)
            {
               if(g_GroupStats[i].killSwitchTriggered)
               {
                  g_GroupStats[i].killSwitchTriggered = false;
                  g_GroupStats[i].peakEquity = g_GroupStats[i].currentEquity;
               }
            }
            
            UpdateButtonColors();
            UpdateGroupButtonColors();
            SavePersistedState();
            Alert(StringFormat("Reset %d provider kill switches (R key)", resetCount));
         }
      }
      
      // Press 'G' to reset first group
      if((lparam == 'G' || lparam == 'g') && ArraySize(g_GroupStats) > 0)
      {
         string groupId = g_GroupStats[0].groupId;
         
         int response = MessageBox(
            StringFormat("Reset GROUP %s kill switch?\n\n(%d providers)\n\n(Keyboard shortcut: G)",
                        groupId, g_GroupStats[0].totalProviders),
            "Confirm Group Reset",
            MB_YESNO | MB_ICONQUESTION
         );
         
         if(response == IDYES)
         {
            ResetGroupKillSwitch(groupId);
            UpdateButtonColors();
            UpdateGroupButtonColors();
            Alert(StringFormat("Reset group: %s (G key)", groupId));
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
                  UpdateGroupButtonColors();
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
   Print("=== SignalHarvester Provider DD Manager v3.2 ===");
   Print("Features: Provider + GROUP Tracking, Peak DD, Chart Buttons, CSV Audit");
   Print("Fix: Killed providers excluded from group aggregation");
   
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
   g_LastStatusLog = TimeCurrent();
   
   CreateChartButtons();
   UpdateButtonColors();
   UpdateGroupButtonColors();
   
   AppendToAuditLog("SYSTEM", "EA_START", 0.0, 
                    StringFormat("Initialized with %d providers, %d groups", 
                                ArraySize(g_ProviderStats), ArraySize(g_GroupStats)));
   
   Print(StringFormat("✓ Initialized %d providers", ArraySize(g_ProviderStats)));
   Print(StringFormat("✓ Group-level tracking: %d groups detected", ArraySize(g_GroupStats)));
   if(ArraySize(g_GroupStats) > 0)
   {
      for(int i = 0; i < ArraySize(g_GroupStats); i++)
      {
         Print(StringFormat("  - Group %s: %d providers", 
                           g_GroupStats[i].groupId, 
                           g_GroupStats[i].totalProviders));
      }
   }
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
   
   // Auto-reset kill switches if enabled
   AutoResetKillSwitches();
   
   if(TimeCurrent() - g_LastButtonUpdate >= 5)
   {
      UpdateButtonColors();
      UpdateGroupButtonColors();
      g_LastButtonUpdate = TimeCurrent();
   }
   
   if(TimeCurrent() - g_LastStateSave >= StateSaveIntervalSeconds)
   {
      SavePersistedState();
      g_LastStateSave = TimeCurrent();
   }
   
   // Log provider status every 5 minutes for diagnostics
   if(TimeCurrent() - g_LastStatusLog >= 300)
   {
      LogProviderStatus();
      g_LastStatusLog = TimeCurrent();
   }
}
//+------------------------------------------------------------------+