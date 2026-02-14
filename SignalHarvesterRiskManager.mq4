//+------------------------------------------------------------------+
//|                         SignalHarvesterRiskManager_v2.mq4        |
//|                    Copyright 2026, Senior MQL4 Engineer          |
//|              WITH STATE PERSISTENCE & FLOATING DD PROTECTION     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "2.10"
#property strict
#property description "Signal portfolio risk manager with floating DD protection"

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Drawdown lookback mode enumeration                               |
//| DD_PEAK_SINCE_START: Use peak from EA start                      |
//| DD_PEAK_ROLLING_HOURS: Use rolling window peak                   |
//+------------------------------------------------------------------+
enum ENUM_DD_LOOKBACK_MODE
{
   DD_PEAK_SINCE_START,      // Track drawdown from EA initialization
   DD_PEAK_ROLLING_HOURS     // Track drawdown from rolling time window
};

//+------------------------------------------------------------------+
//| Provider identification filter mode enumeration                  |
//| FILTER_MAGIC_LIST: Filter by magic numbers                       |
//| FILTER_COMMENT_TAGS: Filter by order comment tags                |
//| FILTER_ALL_NON_MANUAL: Include all non-manual trades             |
//| FILTER_ALL_TRADES: Include all trades regardless of source       |
//+------------------------------------------------------------------+
enum ENUM_PROVIDER_FILTER_MODE
{
   FILTER_MAGIC_LIST,        // Only trades matching magic numbers list
   FILTER_COMMENT_TAGS,      // Only trades matching comment tags
   FILTER_ALL_NON_MANUAL,    // All trades with non-zero magic number
   FILTER_ALL_TRADES         // All open trades in account
};

//+------------------------------------------------------------------+
//| Risk reduction strategy enumeration                              |
//| RISK_BLOCK_NEW_TRADES: Stop opening new positions                |
//| RISK_CLOSE_WORST_FIRST: Close worst performing trades first      |
//| RISK_PRORATA_TRIM: Close positions proportionally across all     |
//+------------------------------------------------------------------+
enum ENUM_RISK_REDUCTION_MODE
{
   RISK_BLOCK_NEW_TRADES,    // Prevent new trades when exposure high
   RISK_CLOSE_WORST_FIRST,   // Liquidate worst performers for risk reduction
   RISK_PRORATA_TRIM         // Trim exposure evenly across all trades
};

//+------------------------------------------------------------------+
//| Automatic stop loss calculation mode enumeration                 |
//| AUTO_SL_NONE: No automatic SL                                    |
//| AUTO_SL_ATR: SL based on ATR volatility                          |
//| AUTO_SL_FIXED_PIPS: Fixed pip SL                                 |
//| AUTO_SL_STRUCTURE: SL based on price structure                   |
//+------------------------------------------------------------------+
enum ENUM_AUTO_SL_MODE
{
   AUTO_SL_NONE,             // Manual SL only
   AUTO_SL_ATR,              // Average True Range based SL
   AUTO_SL_FIXED_PIPS,       // Fixed pip distance SL
   AUTO_SL_STRUCTURE         // Support/resistance based SL
};

//+------------------------------------------------------------------+
//| Logging level enumeration                                        |
//| LOG_ERROR: Critical errors only                                  |
//| LOG_INFO: General information messages                           |
//| LOG_DEBUG: Detailed debugging information                        |
//+------------------------------------------------------------------+
enum ENUM_LOG_LEVEL
{
   LOG_ERROR,                // Only error level messages logged
   LOG_INFO,                 // Error and info level messages logged
   LOG_DEBUG                 // All messages including debug logged
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input double MaxPortfolioDDPercent = 4.0;
input ENUM_DD_LOOKBACK_MODE DDLookbackMode = DD_PEAK_SINCE_START;
input int    RollingHours = 168;
input double MaxRiskNoSLPercentPerTrade = 0.2;
input int    DefaultStopLossPips = 100;

input bool   UseFloatingDDProtection = true;
input double FloatingDDWarningPercent = 2.5;
input double FloatingDDCriticalPercent = 3.5;
input double FloatingDDEmergencyPercent = 4.5;

input bool   IncludeManualTrades = false;
input ENUM_PROVIDER_FILTER_MODE ProviderFilterMode = FILTER_COMMENT_TAGS;
input string MagicList = "12345,67890";
input string CommentTags = "SignalStart,SS:";

input int    MaxConcurrentProviders = 8;
input int    ProviderScoreWindowTrades = 15;
input int    ProviderMinTradesToQualify = 3;
input double ProviderProfitThreshold = -100.0;
input double ProviderMaxDDThreshold = 12.0;
input bool   CloseInactiveProviderOpenTrades = true;

input int    GlobalMaxOpenTrades = 50;
input double GlobalMaxOpenLots = 5.0;
input double MaxSymbolExposurePercent = 2.5;
input double MaxProviderExposurePercent = 1.5;

input bool   EmergencyKillSwitch = true;
input ENUM_RISK_REDUCTION_MODE RiskReductionMode = RISK_CLOSE_WORST_FIRST;
input double TrimStepPercent = 10.0;

input bool   UseEquityStop = true;
input double EquityStopDDPercent = 5.0;
input bool   UseTimeStop = false;
input int    MaxTradeAgeMinutes = 2880;

input bool   UseTrailingEquityLock = false;
input double TrailingEquityLockTriggerPercent = 10.0;
input double TrailingEquityLockPercent = 50.0;

input ENUM_AUTO_SL_MODE AutoSLMode = AUTO_SL_FIXED_PIPS;
input int    ATRPeriod = 14;
input double ATRMultiplier = 2.0;
input int    FixedSLPips = 50;
input int    MaxAllowedSLPips = 200;
input double AutoTPRiskRewardRatio = 2.0;

input ENUM_LOG_LEVEL LogLevel = LOG_INFO;
input int    HistoryScanIntervalSeconds = 120;
input bool   TestMode = true;
input int    StateSaveIntervalSeconds = 300;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
double g_PeakEquity = 0.0;
datetime g_LastHistoryScan = 0;
datetime g_EAStartTime = 0;
bool g_TradingDisabled = false;
double g_EquityLockLevel = 0.0;
datetime g_LastStateSave = 0;
datetime g_LastFloatingDDWarning = 0;

string g_PeakEquityVar;
string g_KillSwitchVar;
string g_EquityLockVar;
string g_EAStartTimeVar;

struct ProviderStats
{
   string   providerId;
   int      totalTrades;
   double   netProfit;
   double   profitFactor;
   double   maxDrawdown;
   double   winRate;
   bool     isActive;
   datetime lastUpdate;
};
ProviderStats g_Providers[];

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
   double   riskAmount;
   double   floatingPL;
};
TradeInfo g_OpenTrades[];

int g_MagicNumbers[];
string g_CommentTagsList[];

//+------------------------------------------------------------------+
//| Logging function                                                 |
//+------------------------------------------------------------------+
void Log(ENUM_LOG_LEVEL level, string message)
{
   if(level > LogLevel) return;
   
   string prefix = "";
   if(level == LOG_ERROR) prefix = "ERROR: ";
   else if(level == LOG_INFO) prefix = "INFO: ";
   else if(level == LOG_DEBUG) prefix = "DEBUG: ";
   
   Print(prefix + message);
}

//+------------------------------------------------------------------+
//| Parse magic number list                                          |
//+------------------------------------------------------------------+
void ParseMagicList()
{
   ArrayResize(g_MagicNumbers, 0);
   
   string magics = MagicList;
   StringReplace(magics, " ", "");
   
   int count = 0;
   while(StringLen(magics) > 0)
   {
      int pos = StringFind(magics, ",");
      string item = (pos >= 0) ? StringSubstr(magics, 0, pos) : magics;
      
      if(StringLen(item) > 0)
      {
         int magic = (int)StringToInteger(item);
         if(magic > 0)
         {
            ArrayResize(g_MagicNumbers, count + 1);
            g_MagicNumbers[count] = magic;
            count++;
         }
      }
      
      if(pos < 0) break;
      magics = StringSubstr(magics, pos + 1);
   }
   
   Log(LOG_INFO, StringFormat("Parsed %d magic numbers", count));
}

//+------------------------------------------------------------------+
//| Parse comment tags list                                          |
//+------------------------------------------------------------------+
void ParseCommentTags()
{
   ArrayResize(g_CommentTagsList, 0);
   
   string tags = CommentTags;
   int count = 0;
   
   while(StringLen(tags) > 0)
   {
      int pos = StringFind(tags, ",");
      string item = (pos >= 0) ? StringSubstr(tags, 0, pos) : tags;
      
      while(StringLen(item) > 0 && StringGetCharacter(item, 0) == 32)
         item = StringSubstr(item, 1);
      while(StringLen(item) > 0 && StringGetCharacter(item, StringLen(item)-1) == 32)
         item = StringSubstr(item, 0, StringLen(item)-1);
      
      if(StringLen(item) > 0)
      {
         ArrayResize(g_CommentTagsList, count + 1);
         g_CommentTagsList[count] = item;
         count++;
      }
      
      if(pos < 0) break;
      tags = StringSubstr(tags, pos + 1);
   }
   
   Log(LOG_INFO, StringFormat("Parsed %d comment tags", count));
}

//+------------------------------------------------------------------+
//| Parse CSV line - HELPER FUNCTION                                 |
//+------------------------------------------------------------------+
int ParseCSVLine(string line, string &fields[])
{
   ArrayResize(fields, 0);
   
   int fieldCount = 0;
   string currentField = "";
   bool inQuotes = false;
   int len = StringLen(line);
   
   for(int i = 0; i < len; i++)
   {
      ushort ch = StringGetCharacter(line, i);
      
      if(ch == 34)
      {
         if(inQuotes && i + 1 < len && StringGetCharacter(line, i + 1) == 34)
         {
            currentField += "\"";
            i++;
         }
         else
         {
            inQuotes = !inQuotes;
         }
      }
      else if(ch == 44 && !inQuotes)
      {
         ArrayResize(fields, fieldCount + 1);
         fields[fieldCount] = currentField;
         fieldCount++;
         currentField = "";
      }
      else
      {
         currentField += ShortToString(ch);
      }
   }
   
   if(StringLen(currentField) > 0 || fieldCount > 0)
   {
      ArrayResize(fields, fieldCount + 1);
      fields[fieldCount] = currentField;
      fieldCount++;
   }
   
   return fieldCount;
}

//+------------------------------------------------------------------+
//| Append to audit log - CORRECTED CSV FORMAT                      |
//+------------------------------------------------------------------+
void AppendToAuditLog(string eventType, string description, double value)
{
   string auditFile = "SHRA_Audit_" + IntegerToString(AccountNumber()) + ".csv";
   int handle = FileOpen(auditFile, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   
   if(handle == INVALID_HANDLE)
   {
      Log(LOG_ERROR, StringFormat("Failed to open audit log: %d", GetLastError()));
      return;
   }
   
   bool needsHeader = (FileSize(handle) == 0);
   FileSeek(handle, 0, SEEK_END);
   
   if(needsHeader)
   {
      FileWriteString(handle, "Timestamp,Event,Description,Value,Equity,Balance,FloatingPL,DDPercent\n");
   }
   
   double balance = AccountBalance();
   double equity = AccountEquity();
   double floatingPL = equity - balance;
   double dd = 0.0;
   if(g_PeakEquity > 0) dd = ((g_PeakEquity - equity) / g_PeakEquity) * 100.0;
   
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   
   string safeDesc = description;
   StringReplace(safeDesc, "\"", "\"\"");
   if(StringFind(safeDesc, ",") >= 0) safeDesc = "\"" + safeDesc + "\"";
   
   string row = timestamp + "," +
                eventType + "," +
                safeDesc + "," +
                DoubleToString(value, 2) + "," +
                DoubleToString(equity, 2) + "," +
                DoubleToString(balance, 2) + "," +
                DoubleToString(floatingPL, 2) + "," +
                DoubleToString(dd, 2) + "\n";
   
   FileWriteString(handle, row);
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Save configuration snapshot - CORRECTED FORMAT                   |
//+------------------------------------------------------------------+
void SaveConfigurationSnapshot()
{
   string configFile = "SHRA_Config_" + IntegerToString(AccountNumber()) + ".txt";
   int handle = FileOpen(configFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
   
   if(handle == INVALID_HANDLE) return;
   
   string config = "=== SignalHarvesterRiskManager v2.10 ===\n";
   config += "Timestamp: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\n";
   config += "Account: " + IntegerToString(AccountNumber()) + "\n";
   config += "Broker: " + AccountCompany() + "\n";
   config += "Balance: " + DoubleToString(AccountBalance(), 2) + "\n\n";
   config += "=== Risk Parameters ===\n";
   config += "MaxPortfolioDDPercent: " + DoubleToString(MaxPortfolioDDPercent, 2) + "\n";
   config += "EquityStopDDPercent: " + DoubleToString(EquityStopDDPercent, 2) + "\n";
   config += "MaxProviderExposurePercent: " + DoubleToString(MaxProviderExposurePercent, 2) + "\n";
   config += "MaxSymbolExposurePercent: " + DoubleToString(MaxSymbolExposurePercent, 2) + "\n\n";
   config += "=== Floating DD Protection ===\n";
   config += "UseFloatingDDProtection: " + (UseFloatingDDProtection ? "true" : "false") + "\n";
   config += "FloatingDDWarningPercent: " + DoubleToString(FloatingDDWarningPercent, 2) + "\n";
   config += "FloatingDDCriticalPercent: " + DoubleToString(FloatingDDCriticalPercent, 2) + "\n";
   config += "FloatingDDEmergencyPercent: " + DoubleToString(FloatingDDEmergencyPercent, 2) + "\n\n";
   config += "=== Provider Settings ===\n";
   config += "MaxConcurrentProviders: " + IntegerToString(MaxConcurrentProviders) + "\n";
   config += "ProviderMaxDDThreshold: " + DoubleToString(ProviderMaxDDThreshold, 2) + "\n";
   config += "ProviderScoreWindowTrades: " + IntegerToString(ProviderScoreWindowTrades) + "\n\n";
   config += "=== Trade Limits ===\n";
   config += "GlobalMaxOpenTrades: " + IntegerToString(GlobalMaxOpenTrades) + "\n";
   config += "GlobalMaxOpenLots: " + DoubleToString(GlobalMaxOpenLots, 2) + "\n\n";
   config += "=== Current State ===\n";
   config += "Peak Equity: " + DoubleToString(g_PeakEquity, 2) + "\n";
   config += "Current Equity: " + DoubleToString(AccountEquity(), 2) + "\n";
   config += "Kill Switch: " + (g_TradingDisabled ? "ACTIVE" : "OFF") + "\n";
   config += "Equity Lock Level: " + DoubleToString(g_EquityLockLevel, 2) + "\n";
   config += "EA Start Time: " + TimeToString(g_EAStartTime) + "\n";
   
   FileWriteString(handle, config);
   FileClose(handle);
   Log(LOG_DEBUG, "Configuration saved");
}

//+------------------------------------------------------------------+
//| Save provider stats - CORRECTED CSV FORMAT                      |
//+------------------------------------------------------------------+
bool SaveProviderStatsToFile()
{
   string providerFile = "SHRA_Providers_" + IntegerToString(AccountNumber()) + ".csv";
   int handle = FileOpen(providerFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
   
   if(handle == INVALID_HANDLE)
   {
      Log(LOG_ERROR, StringFormat("Failed to save providers: %d", GetLastError()));
      return false;
   }
   
   FileWriteString(handle, "ProviderId,TotalTrades,NetProfit,ProfitFactor,MaxDrawdown,WinRate,IsActive,LastUpdate\n");
   
   for(int i = 0; i < ArraySize(g_Providers); i++)
   {
      string providerId = g_Providers[i].providerId;
      StringReplace(providerId, "\"", "\"\"");
      if(StringFind(providerId, ",") >= 0) providerId = "\"" + providerId + "\"";
      
      string row = providerId + "," +
                   IntegerToString(g_Providers[i].totalTrades) + "," +
                   DoubleToString(g_Providers[i].netProfit, 2) + "," +
                   DoubleToString(g_Providers[i].profitFactor, 2) + "," +
                   DoubleToString(g_Providers[i].maxDrawdown, 2) + "," +
                   DoubleToString(g_Providers[i].winRate, 2) + "," +
                   (g_Providers[i].isActive ? "1" : "0") + "," +
                   IntegerToString((int)g_Providers[i].lastUpdate) + "\n";
      
      FileWriteString(handle, row);
   }
   
   FileClose(handle);
   Log(LOG_DEBUG, StringFormat("Saved %d provider stats", ArraySize(g_Providers)));
   return true;
}

//+------------------------------------------------------------------+
//| Load provider stats - CORRECTED CSV FORMAT                      |
//+------------------------------------------------------------------+
bool LoadProviderStatsFromFile()
{
   string providerFile = "SHRA_Providers_" + IntegerToString(AccountNumber()) + ".csv";
   
   if(!FileIsExist(providerFile))
   {
      Log(LOG_INFO, "No saved provider stats");
      return false;
   }
   
   int handle = FileOpen(providerFile, FILE_READ|FILE_TXT|FILE_ANSI);
   
   if(handle == INVALID_HANDLE)
   {
      Log(LOG_ERROR, StringFormat("Failed to load providers: %d", GetLastError()));
      return false;
   }
   
   ArrayResize(g_Providers, 0);
   string header = FileReadString(handle);
   int count = 0;
   
   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      if(StringLen(line) == 0) continue;
      
      string fields[];
      int fieldCount = ParseCSVLine(line, fields);
      
      if(fieldCount < 8)
      {
         Log(LOG_ERROR, StringFormat("Invalid provider line: %s", line));
         continue;
      }
      
      ProviderStats stats;
      stats.providerId = fields[0];
      stats.totalTrades = (int)StringToInteger(fields[1]);
      stats.netProfit = StringToDouble(fields[2]);
      stats.profitFactor = StringToDouble(fields[3]);
      stats.maxDrawdown = StringToDouble(fields[4]);
      stats.winRate = StringToDouble(fields[5]);
      stats.isActive = (fields[6] == "1");
      stats.lastUpdate = (datetime)StringToInteger(fields[7]);
      
      int size = ArraySize(g_Providers);
      ArrayResize(g_Providers, size + 1);
      g_Providers[size] = stats;
      count++;
   }
   
   FileClose(handle);
   Log(LOG_INFO, StringFormat("Loaded %d providers", count));
   return true;
}

//+------------------------------------------------------------------+
//| Load persisted state                                             |
//+------------------------------------------------------------------+
void LoadPersistedState()
{
   g_PeakEquityVar = "SHRA_PeakEquity_" + IntegerToString(AccountNumber());
   g_KillSwitchVar = "SHRA_KillSwitch_" + IntegerToString(AccountNumber());
   g_EquityLockVar = "SHRA_EquityLock_" + IntegerToString(AccountNumber());
   g_EAStartTimeVar = "SHRA_StartTime_" + IntegerToString(AccountNumber());
   
   if(GlobalVariableCheck(g_PeakEquityVar))
   {
      double savedPeak = GlobalVariableGet(g_PeakEquityVar);
      g_PeakEquity = MathMax(savedPeak, AccountEquity());
      Log(LOG_INFO, StringFormat("Peak restored: %.2f", g_PeakEquity));
   }
   else
   {
      g_PeakEquity = AccountEquity();
      GlobalVariableSet(g_PeakEquityVar, g_PeakEquity);
      Log(LOG_INFO, StringFormat("Peak initialized: %.2f", g_PeakEquity));
   }
   
   g_TradingDisabled = false;
   if(GlobalVariableCheck(g_KillSwitchVar))
   {
      if(GlobalVariableGet(g_KillSwitchVar) > 0)
      {
         g_TradingDisabled = true;
         Log(LOG_ERROR, "Kill switch active from previous session");
      }
   }
   
   if(UseTrailingEquityLock && GlobalVariableCheck(g_EquityLockVar))
   {
      g_EquityLockLevel = GlobalVariableGet(g_EquityLockVar);
      Log(LOG_INFO, StringFormat("Equity lock restored: %.2f", g_EquityLockLevel));
   }
   
   if(GlobalVariableCheck(g_EAStartTimeVar))
   {
      g_EAStartTime = (datetime)GlobalVariableGet(g_EAStartTimeVar);
   }
   else
   {
      g_EAStartTime = TimeCurrent();
      GlobalVariableSet(g_EAStartTimeVar, (double)g_EAStartTime);
   }
   
   g_LastStateSave = TimeCurrent();
   g_LastFloatingDDWarning = 0;
}

//+------------------------------------------------------------------+
//| Save persisted state                                             |
//+------------------------------------------------------------------+
void SavePersistedState()
{
   GlobalVariableSet(g_PeakEquityVar, g_PeakEquity);
   GlobalVariableSet(g_KillSwitchVar, g_TradingDisabled ? 1.0 : 0.0);
   GlobalVariableSet(g_EquityLockVar, g_EquityLockLevel);
   GlobalVariableSet(g_EAStartTimeVar, (double)g_EAStartTime);
   
   Log(LOG_DEBUG, "State saved");
}

//+------------------------------------------------------------------+
//| Calculate current drawdown                                       |
//+------------------------------------------------------------------+
double CalculateCurrentDrawdown()
{
   double equity = AccountEquity();
   if(g_PeakEquity <= 0) return 0.0;
   
   double dd = ((g_PeakEquity - equity) / g_PeakEquity) * 100.0;
   return MathMax(0.0, dd);
}

//+------------------------------------------------------------------+
//| Calculate signal floating PL                                     |
//+------------------------------------------------------------------+
double CalculateSignalFloatingPL()
{
   double total = 0.0;
   for(int i = 0; i < ArraySize(g_OpenTrades); i++)
   {
      total += g_OpenTrades[i].floatingPL;
   }
   return total;
}

//+------------------------------------------------------------------+
//| Calculate signal floating DD                                     |
//+------------------------------------------------------------------+
double CalculateSignalFloatingDD()
{
   double balance = AccountBalance();
   double floatingPL = CalculateSignalFloatingPL();
   
   if(balance <= 0 || floatingPL >= 0) return 0.0;
   
   return (-1.0 * floatingPL / balance) * 100.0;
}

//+------------------------------------------------------------------+
//| Calculate allowed exposure                                       |
//+------------------------------------------------------------------+
double CalculateAllowedExposure(double currentDD)
{
   if(currentDD >= MaxPortfolioDDPercent) return 0.0;
   
   return MaxPortfolioDDPercent * (1.0 - (currentDD / MaxPortfolioDDPercent));
}

//+------------------------------------------------------------------+
//| Identify provider                                                |
//+------------------------------------------------------------------+
string IdentifyProvider(int magic, string comment)
{
   if(magic != 0) return "Magic_" + IntegerToString(magic);
   
   for(int i = 0; i < ArraySize(g_CommentTagsList); i++)
   {
      if(StringFind(comment, g_CommentTagsList[i]) >= 0)
         return g_CommentTagsList[i];
   }
   
   return "Manual";
}

//+------------------------------------------------------------------+
//| Calculate trade risk                                             |
//+------------------------------------------------------------------+
double CalculateTradeRisk(int tradeIndex)
{
   if(tradeIndex >= ArraySize(g_OpenTrades)) return 0.0;
   
   TradeInfo trade = g_OpenTrades[tradeIndex];
   
   if(trade.sl > 0)
   {
      double slDistance = MathAbs(trade.openPrice - trade.sl);
      double pointValue = MarketInfo(trade.symbol, MODE_TICKVALUE);
      double pipSize = MarketInfo(trade.symbol, MODE_POINT);
      
      if(StringFind(trade.symbol, "JPY") >= 0) pipSize *= 10;
      
      double pips = slDistance / pipSize;
      return pips * pointValue * trade.lots;
   }
   
   return AccountEquity() * (MaxRiskNoSLPercentPerTrade / 100.0);
}

//+------------------------------------------------------------------+
//| Check if should manage trade                                     |
//+------------------------------------------------------------------+
bool ShouldManageTrade(int magic, string comment)
{
   if(ProviderFilterMode == FILTER_ALL_TRADES) return true;
   if(ProviderFilterMode == FILTER_ALL_NON_MANUAL) return (magic != 0);
   
   if(ProviderFilterMode == FILTER_MAGIC_LIST)
   {
      for(int i = 0; i < ArraySize(g_MagicNumbers); i++)
      {
         if(magic == g_MagicNumbers[i]) return true;
      }
      return (IncludeManualTrades && magic == 0);
   }
   
   if(ProviderFilterMode == FILTER_COMMENT_TAGS)
   {
      for(int i = 0; i < ArraySize(g_CommentTagsList); i++)
      {
         if(StringFind(comment, g_CommentTagsList[i]) >= 0) return true;
      }
      return (IncludeManualTrades && magic == 0);
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Scan open orders                                                 |
//+------------------------------------------------------------------+
void ScanOpenOrders()
{
   ArrayResize(g_OpenTrades, 0);
   
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderType() > OP_SELL) continue;
      if(!ShouldManageTrade(OrderMagicNumber(), OrderComment())) continue;
      
      int size = ArraySize(g_OpenTrades);
      ArrayResize(g_OpenTrades, size + 1);
      
      g_OpenTrades[size].ticket = OrderTicket();
      g_OpenTrades[size].providerId = IdentifyProvider(OrderMagicNumber(), OrderComment());
      g_OpenTrades[size].symbol = OrderSymbol();
      g_OpenTrades[size].orderType = OrderType();
      g_OpenTrades[size].lots = OrderLots();
      g_OpenTrades[size].openPrice = OrderOpenPrice();
      g_OpenTrades[size].sl = OrderStopLoss();
      g_OpenTrades[size].tp = OrderTakeProfit();
      g_OpenTrades[size].openTime = OrderOpenTime();
      g_OpenTrades[size].comment = OrderComment();
      g_OpenTrades[size].magic = OrderMagicNumber();
      g_OpenTrades[size].riskAmount = CalculateTradeRisk(size);
      g_OpenTrades[size].floatingPL = OrderProfit() + OrderSwap() + OrderCommission();
   }
   
   Log(LOG_DEBUG, StringFormat("Scanned %d trades", ArraySize(g_OpenTrades)));
}

//+------------------------------------------------------------------+
//| Calculate total exposure                                         |
//+------------------------------------------------------------------+
double CalculateTotalExposure()
{
   double total = 0.0;
   double equity = AccountEquity();
   
   if(equity <= 0) return 0.0;
   
   for(int i = 0; i < ArraySize(g_OpenTrades); i++)
   {
      total += g_OpenTrades[i].riskAmount;
   }
   
   return (total / equity) * 100.0;
}

//+------------------------------------------------------------------+
//| Close order                                                       |
//+------------------------------------------------------------------+
bool CloseOrder(int ticket, string reason)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return false;
   
   double closePrice = (OrderType() == OP_BUY) ? 
                       MarketInfo(OrderSymbol(), MODE_BID) : 
                       MarketInfo(OrderSymbol(), MODE_ASK);
   
   bool result = OrderClose(ticket, OrderLots(), closePrice, 3, clrRed);
   
   if(result)
   {
      Log(LOG_INFO, StringFormat("Closed #%d: %s", ticket, reason));
   }
   else
   {
      Log(LOG_ERROR, StringFormat("Failed #%d: %d", ticket, GetLastError()));
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Find worst trade                                                 |
//+------------------------------------------------------------------+
int FindWorstTrade()
{
   if(ArraySize(g_OpenTrades) == 0) return -1;
   
   int worstIdx = 0;
   double worstPL = g_OpenTrades[0].floatingPL;
   
   for(int i = 1; i < ArraySize(g_OpenTrades); i++)
   {
      if(g_OpenTrades[i].floatingPL < worstPL)
      {
         worstPL = g_OpenTrades[i].floatingPL;
         worstIdx = i;
      }
   }
   
   return worstIdx;
}

//+------------------------------------------------------------------+
//| Close worst trades                                               |
//+------------------------------------------------------------------+
void CloseWorstTrades(double percentage)
{
   int total = ArraySize(g_OpenTrades);
   if(total == 0) return;
   
   int sortedIdx[];
   ArrayResize(sortedIdx, total);
   
   for(int i = 0; i < total; i++) sortedIdx[i] = i;
   
   for(int i = 0; i < total - 1; i++)
   {
      for(int j = 0; j < total - i - 1; j++)
      {
         if(g_OpenTrades[sortedIdx[j]].floatingPL > g_OpenTrades[sortedIdx[j+1]].floatingPL)
         {
            int temp = sortedIdx[j];
            sortedIdx[j] = sortedIdx[j+1];
            sortedIdx[j+1] = temp;
         }
      }
   }
   
   int toClose = (int)MathCeil(total * percentage);
   int closed = 0;
   
   for(int i = 0; i < toClose && i < total; i++)
   {
      int idx = sortedIdx[i];
      if(CloseOrder(g_OpenTrades[idx].ticket, "Floating DD critical"))
      {
         closed++;
      }
   }
   
   Log(LOG_INFO, StringFormat("Closed %d trades", closed));
}

//+------------------------------------------------------------------+
//| Handle exposure breach                                           |
//+------------------------------------------------------------------+
void HandleExposureBreach(double currentExp, double allowedExp)
{
   AppendToAuditLog("EXPOSURE_BREACH",
                    StringFormat("%.2f > %.2f", currentExp, allowedExp),
                    currentExp);
   
   if(RiskReductionMode == RISK_CLOSE_WORST_FIRST)
   {
      while(CalculateTotalExposure() > allowedExp && ArraySize(g_OpenTrades) > 0)
      {
         int idx = FindWorstTrade();
         if(idx >= 0)
         {
            CloseOrder(g_OpenTrades[idx].ticket, "Exposure breach");
            ScanOpenOrders();
         }
         else break;
      }
   }
}

//+------------------------------------------------------------------+
//| Activate kill switch                                             |
//+------------------------------------------------------------------+
void ActivateKillSwitch()
{
   Log(LOG_ERROR, "KILL SWITCH ACTIVATED");
   
   double currentDD = CalculateCurrentDrawdown();
   double floatingDD = CalculateSignalFloatingDD();
   
   AppendToAuditLog("KILL_SWITCH", 
                    StringFormat("DD:%.2f FloatDD:%.2f Trades:%d", 
                                 currentDD, floatingDD, ArraySize(g_OpenTrades)),
                    AccountEquity());
   
   int closed = 0;
   for(int i = ArraySize(g_OpenTrades) - 1; i >= 0; i--)
   {
      if(CloseOrder(g_OpenTrades[i].ticket, "Kill switch")) closed++;
   }
   
   GlobalVariableSet(g_KillSwitchVar, 1.0);
   g_TradingDisabled = true;
   SaveProviderStatsToFile();
   
   Log(LOG_ERROR, StringFormat("%d trades closed", closed));
   Alert("KILL SWITCH: ", closed, " trades closed");
}

//+------------------------------------------------------------------+
//| Update peak equity                                               |
//+------------------------------------------------------------------+
void UpdatePeakEquity()
{
   double equity = AccountEquity();
   
   if(equity > g_PeakEquity)
   {
      double oldPeak = g_PeakEquity;
      g_PeakEquity = equity;
      GlobalVariableSet(g_PeakEquityVar, g_PeakEquity);
      
      AppendToAuditLog("PEAK_UPDATE", 
                       StringFormat("%.2f to %.2f", oldPeak, g_PeakEquity),
                       g_PeakEquity);
      
      Log(LOG_DEBUG, StringFormat("New peak: %.2f", g_PeakEquity));
   }
}

//+------------------------------------------------------------------+
//| Check trailing equity lock                                       |
//+------------------------------------------------------------------+
void CheckTrailingEquityLock()
{
   double equity = AccountEquity();
   double balance = AccountBalance();
   double gain = equity - balance;
   double gainPct = (balance > 0) ? (gain / balance) * 100.0 : 0.0;
   
   if(gainPct >= TrailingEquityLockTriggerPercent)
   {
      double lockLevel = balance + (gain * TrailingEquityLockPercent / 100.0);
      
      if(lockLevel > g_EquityLockLevel)
      {
         g_EquityLockLevel = lockLevel;
         GlobalVariableSet(g_EquityLockVar, g_EquityLockLevel);
         
         AppendToAuditLog("EQUITY_LOCK_UPDATE",
                          StringFormat("Lock: %.2f Gain: %.2f%%", g_EquityLockLevel, gainPct),
                          g_EquityLockLevel);
      }
      
      if(equity < g_EquityLockLevel)
      {
         Log(LOG_ERROR, StringFormat("Lock breach: %.2f < %.2f", equity, g_EquityLockLevel));
         
         AppendToAuditLog("EQUITY_LOCK_BREACH",
                          StringFormat("Equity %.2f below lock %.2f", equity, g_EquityLockLevel),
                          equity);
         
         ActivateKillSwitch();
      }
   }
}

//+------------------------------------------------------------------+
//| Placeholder functions                                            |
//+------------------------------------------------------------------+
void UpdateProviderStatsFromHistory() { }
void EnforceGlobalCaps() { }
void EnforceSymbolCaps() { }
void EnforceProviderCaps() { }
void EnforceTimeStops() { }
void ApplyAutoSLTP() { }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Log(LOG_INFO, "SignalHarvesterRiskManager v2.10 Starting");
   Log(LOG_INFO, "Features: State Persistence + Floating DD Protection + Corrected CSV");
   
   LoadPersistedState();
   ParseMagicList();
   ParseCommentTags();
   LoadProviderStatsFromFile();
   SaveConfigurationSnapshot();
   
   Log(LOG_INFO, StringFormat("Peak:%.2f KillSwitch:%s Providers:%d", 
       g_PeakEquity, g_TradingDisabled ? "ON" : "OFF", ArraySize(g_Providers)));
   
   if(UseFloatingDDProtection)
   {
      Log(LOG_INFO, StringFormat("FloatDD: Warn=%.1f%% Crit=%.1f%% Emerg=%.1f%%",
          FloatingDDWarningPercent, FloatingDDCriticalPercent, FloatingDDEmergencyPercent));
   }
   
   AppendToAuditLog("EA_START", "EA initialized successfully", AccountEquity());
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Log(LOG_INFO, StringFormat("EA Stopped (Reason:%d)", reason));
   
   SavePersistedState();
   SaveProviderStatsToFile();
   
   AppendToAuditLog("EA_STOP", StringFormat("Reason:%d", reason), AccountEquity());
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_TradingDisabled) return;
   
   UpdatePeakEquity();
   
   double currentDD = CalculateCurrentDrawdown();
   
   ScanOpenOrders();
   
   double floatingDD = CalculateSignalFloatingDD();
   double floatingPL = CalculateSignalFloatingPL();
   
   if(UseFloatingDDProtection)
   {
      if(floatingDD >= FloatingDDWarningPercent)
      {
         if(TimeCurrent() - g_LastFloatingDDWarning >= 300)
         {
            Log(LOG_ERROR, StringFormat("WARNING: FloatDD %.2f%% (%.2f)", floatingDD, floatingPL));
            AppendToAuditLog("FLOAT_WARN", StringFormat("FloatDD:%.2f%% FloatPL:%.2f", floatingDD, floatingPL), floatingDD);
            g_LastFloatingDDWarning = TimeCurrent();
         }
      }
      
      if(floatingDD >= FloatingDDCriticalPercent)
      {
         Log(LOG_ERROR, StringFormat("CRITICAL: FloatDD %.2f%% - Closing worst 20%%", floatingDD));
         AppendToAuditLog("FLOAT_CRIT", StringFormat("FloatDD:%.2f%% closing worst trades", floatingDD), floatingDD);
         
         CloseWorstTrades(0.2);
         ScanOpenOrders();
         floatingDD = CalculateSignalFloatingDD();
         floatingPL = CalculateSignalFloatingPL();
         
         Log(LOG_INFO, StringFormat("After closing: FloatDD %.2f%% (%.2f)", floatingDD, floatingPL));
      }
      
      if(floatingDD >= FloatingDDEmergencyPercent)
      {
         Log(LOG_ERROR, StringFormat("EMERGENCY: FloatDD %.2f%% - KILL SWITCH", floatingDD));
         AppendToAuditLog("FLOAT_EMERG", StringFormat("FloatDD:%.2f%% emergency kill", floatingDD), floatingDD);
         ActivateKillSwitch();
         return;
      }
   }
   
   if(UseEquityStop && currentDD >= EquityStopDDPercent)
   {
      Log(LOG_ERROR, StringFormat("EQUITY STOP: %.2f%% >= %.2f%%", currentDD, EquityStopDDPercent));
      ActivateKillSwitch();
      return;
   }
   
   if(UseTrailingEquityLock) CheckTrailingEquityLock();
   
   if(TimeCurrent() - g_LastHistoryScan >= HistoryScanIntervalSeconds)
   {
      UpdateProviderStatsFromHistory();
      g_LastHistoryScan = TimeCurrent();
   }
   
   if(UseTimeStop) EnforceTimeStops();
   
   double totalExp = CalculateTotalExposure();
   double allowedExp = CalculateAllowedExposure(currentDD);
   
   if(TestMode)
   {
      static datetime lastPrint = 0;
      if(TimeCurrent() - lastPrint >= 10)
      {
         string status = "";
         if(floatingDD >= FloatingDDCriticalPercent) status = " CRIT";
         else if(floatingDD >= FloatingDDWarningPercent) status = " WARN";
         
         Log(LOG_INFO, StringFormat("TEST Eq:%.0f Pk:%.0f DD:%.2f%% Flt:%.2f%%(%.0f)%s Exp:%.2f%% T:%d",
             AccountEquity(), g_PeakEquity, currentDD, floatingDD, floatingPL, status, totalExp, ArraySize(g_OpenTrades)));
         
         lastPrint = TimeCurrent();
      }
   }
   
   if(totalExp > allowedExp)
   {
      Log(LOG_ERROR, StringFormat("EXPOSURE: %.2f%% > %.2f%%", totalExp, allowedExp));
      HandleExposureBreach(totalExp, allowedExp);
   }
   
   EnforceGlobalCaps();
   EnforceSymbolCaps();
   EnforceProviderCaps();
   ApplyAutoSLTP();
   
   if(TimeCurrent() - g_LastStateSave >= StateSaveIntervalSeconds)
   {
      SavePersistedState();
      SaveProviderStatsToFile();
      g_LastStateSave = TimeCurrent();
      Log(LOG_DEBUG, "Periodic save completed");
   }
}
//+------------------------------------------------------------------+