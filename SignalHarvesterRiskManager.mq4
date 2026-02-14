//+------------------------------------------------------------------+
//|                         SignalHarvesterRiskManager_v2.mq4        |
//|                    Copyright 2026, Senior MQL4 Engineer          |
//|                         WITH STATE PERSISTENCE                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "2.00"
#property strict
#property description "Signal portfolio risk manager with state persistence"

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_DD_LOOKBACK_MODE
{
   DD_PEAK_SINCE_START,      // Peak equity since EA start
   DD_PEAK_ROLLING_HOURS     // Peak equity in rolling N hours
};

enum ENUM_PROVIDER_FILTER_MODE
{
   FILTER_MAGIC_LIST,        // Use MagicList CSV
   FILTER_COMMENT_TAGS,      // Use CommentTags CSV
   FILTER_ALL_NON_MANUAL,    // All trades with magic != 0
   FILTER_ALL_TRADES         // Manage all trades including manual
};

enum ENUM_RISK_REDUCTION_MODE
{
   RISK_BLOCK_NEW_TRADES,    // Only block new trades
   RISK_CLOSE_WORST_FIRST,   // Close worst trades (most negative P/L)
   RISK_PRORATA_TRIM         // Close positions proportionally
};

enum ENUM_AUTO_SL_MODE
{
   AUTO_SL_NONE,             // No automatic stop loss
   AUTO_SL_ATR,              // ATR-based stop loss
   AUTO_SL_FIXED_PIPS,       // Fixed pips stop loss
   AUTO_SL_STRUCTURE         // Recent swing structure
};

enum ENUM_LOG_LEVEL
{
   LOG_ERROR,
   LOG_INFO,
   LOG_DEBUG
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
// === DRAWDOWN & EXPOSURE CONTROLS ===
input double MaxPortfolioDDPercent = 4.0;              // Maximum portfolio drawdown budget (%)
input ENUM_DD_LOOKBACK_MODE DDLookbackMode = DD_PEAK_SINCE_START;
input int    RollingHours = 168;                        // Rolling hours for DD calculation
input double MaxRiskNoSLPercentPerTrade = 0.2;          // Risk per trade with no SL (%)
input int    DefaultStopLossPips = 100;                 // Default SL in pips

// === PROVIDER FILTERING ===
input bool   IncludeManualTrades = false;               // Include manual trades?
input ENUM_PROVIDER_FILTER_MODE ProviderFilterMode = FILTER_COMMENT_TAGS;
input string MagicList = "12345,67890";                 // CSV list of magic numbers
input string CommentTags = "SignalStart,SS:";           // CSV comment substrings

// === PROVIDER PERFORMANCE ===
input int    MaxConcurrentProviders = 8;                // Max active providers
input int    ProviderScoreWindowTrades = 15;            // Last N trades for scoring
input int    ProviderMinTradesToQualify = 3;            // Min trades to qualify
input double ProviderProfitThreshold = -100.0;          // Min net profit threshold
input double ProviderMaxDDThreshold = 12.0;             // Max provider DD (%)
input bool   CloseInactiveProviderOpenTrades = true;    // Close inactive provider trades?

// === RISK CAPS ===
input int    GlobalMaxOpenTrades = 50;                  // Max open trades (increased)
input double GlobalMaxOpenLots = 10.0;                   // Max open lots (increased)
input double MaxSymbolExposurePercent = 2.5;            // Max per symbol (%)
input double MaxProviderExposurePercent = 1.5;          // Max per provider (%)

// === EMERGENCY CONTROLS ===
input bool   EmergencyKillSwitch = true;                // Emergency kill all?
input ENUM_RISK_REDUCTION_MODE RiskReductionMode = RISK_CLOSE_WORST_FIRST;
input double TrimStepPercent = 10.0;                    // Trim step %

// === EQUITY & TIME STOPS ===
input bool   UseEquityStop = true;                      // Use hard equity stop?
input double EquityStopDDPercent = 5.0;                 // Hard stop DD %
input bool   UseTimeStop = false;                       // Close old trades?
input int    MaxTradeAgeMinutes = 2880;                 // Max trade age (48h)

// === TRAILING EQUITY LOCK ===
input bool   UseTrailingEquityLock = false;             // Lock profits?
input double TrailingEquityLockTriggerPercent = 10.0;   // Trigger % gain
input double TrailingEquityLockPercent = 50.0;          // Lock % of gains

// === AUTO SL/TP ===
input ENUM_AUTO_SL_MODE AutoSLMode = AUTO_SL_FIXED_PIPS;
input int    ATRPeriod = 14;                            // ATR period
input double ATRMultiplier = 2.0;                       // ATR multiplier
input int    FixedSLPips = 50;                          // Fixed SL pips
input int    MaxAllowedSLPips = 200;                    // Max SL distance
input double AutoTPRiskRewardRatio = 2.0;               // Auto TP RR ratio

// === LOGGING & PERSISTENCE ===
input ENUM_LOG_LEVEL LogLevel = LOG_INFO;               // Logging level
input int    HistoryScanIntervalSeconds = 120;          // History scan interval
input bool   TestMode = false;                          // Test mode
input int    StateSaveIntervalSeconds = 300;            // State save interval (5 min)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
double g_PeakEquity = 0.0;
datetime g_LastHistoryScan = 0;
datetime g_EAStartTime = 0;
bool g_TradingDisabled = false;
double g_EquityLockLevel = 0.0;
datetime g_LastStateSave = 0;

// Persistence variable names
string g_PeakEquityVar;
string g_KillSwitchVar;
string g_EquityLockVar;
string g_EAStartTimeVar;

// Provider data structures
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

// Trade info structure
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

// Parsed input lists
int g_MagicNumbers[];
string g_CommentTagsList[];

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS - MUST BE DEFINED BEFORE USE                    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Logging function                                                 |
//+------------------------------------------------------------------+
void Log(ENUM_LOG_LEVEL level, string message)
{
   if(level > LogLevel) return;
   
   string prefix = "";
   if(level == LOG_ERROR) prefix = "ERROR: ";
   if(level == LOG_INFO) prefix = "INFO: ";
   if(level == LOG_DEBUG) prefix = "DEBUG: ";
   
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
      
      // Trim whitespace
      while(StringLen(item) > 0 && StringGetCharacter(item, 0) == ' ')
         item = StringSubstr(item, 1);
      while(StringLen(item) > 0 && StringGetCharacter(item, StringLen(item)-1) == ' ')
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
//| Append event to audit log                                        |
//+------------------------------------------------------------------+
void AppendToAuditLog(string eventType, string description, double value)
{
   string auditFile = "SHRA_Audit_" + IntegerToString(AccountNumber()) + ".csv";
   int handle = FileOpen(auditFile, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
   
   if(handle == INVALID_HANDLE) return;
   
   // If file is empty, write header
   if(FileSize(handle) == 0)
   {
      FileSeek(handle, 0, SEEK_SET);
      FileWrite(handle, "Timestamp", "Event", "Description", "Value", "Equity", "DD%", "ActiveProviders");
   }
   
   // Append to end
   FileSeek(handle, 0, SEEK_END);
   
   int activeProviders = 0;
   for(int i = 0; i < ArraySize(g_Providers); i++)
   {
      if(g_Providers[i].isActive) activeProviders++;
   }
   
   double currentDD = 0.0; // Will be calculated properly in full version
   
   FileWrite(handle,
             TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
             eventType,
             description,
             DoubleToString(value, 2),
             DoubleToString(AccountEquity(), 2),
             DoubleToString(currentDD, 2),
             IntegerToString(activeProviders));
   
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Save configuration snapshot for audit                            |
//+------------------------------------------------------------------+
void SaveConfigurationSnapshot()
{
   string configFile = "SHRA_Config_" + IntegerToString(AccountNumber()) + ".txt";
   int handle = FileOpen(configFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
   
   if(handle == INVALID_HANDLE) return;
   
   FileWrite(handle, "=== SignalHarvesterRiskManager Configuration Snapshot ===");
   FileWrite(handle, "Timestamp: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   FileWrite(handle, "Account: " + IntegerToString(AccountNumber()));
   FileWrite(handle, "Broker: " + AccountCompany());
   FileWrite(handle, "Balance: " + DoubleToString(AccountBalance(), 2));
   FileWrite(handle, "");
   FileWrite(handle, "=== Risk Parameters ===");
   FileWrite(handle, "MaxPortfolioDDPercent: " + DoubleToString(MaxPortfolioDDPercent, 2));
   FileWrite(handle, "MaxProviderExposurePercent: " + DoubleToString(MaxProviderExposurePercent, 2));
   FileWrite(handle, "MaxSymbolExposurePercent: " + DoubleToString(MaxSymbolExposurePercent, 2));
   FileWrite(handle, "EquityStopDDPercent: " + DoubleToString(EquityStopDDPercent, 2));
   FileWrite(handle, "");
   FileWrite(handle, "=== Provider Settings ===");
   FileWrite(handle, "MaxConcurrentProviders: " + IntegerToString(MaxConcurrentProviders));
   FileWrite(handle, "ProviderMaxDDThreshold: " + DoubleToString(ProviderMaxDDThreshold, 2));
   FileWrite(handle, "ProviderScoreWindowTrades: " + IntegerToString(ProviderScoreWindowTrades));
   FileWrite(handle, "");
   FileWrite(handle, "=== Current State ===");
   FileWrite(handle, "Peak Equity: " + DoubleToString(g_PeakEquity, 2));
   FileWrite(handle, "Current Equity: " + DoubleToString(AccountEquity(), 2));
   FileWrite(handle, "Kill Switch: " + (g_TradingDisabled ? "ACTIVE" : "OFF"));
   
   FileClose(handle);
   
   Log(LOG_DEBUG, "Configuration snapshot saved");
}

//+------------------------------------------------------------------+
//| Save provider stats to CSV file                                  |
//+------------------------------------------------------------------+
bool SaveProviderStatsToFile()
{
   string providerFile = "SHRA_Providers_" + IntegerToString(AccountNumber()) + ".csv";
   int handle = FileOpen(providerFile, FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
   
   if(handle == INVALID_HANDLE)
   {
      Log(LOG_ERROR, StringFormat("Failed to save provider stats: %d", GetLastError()));
      return false;
   }
   
   // Write header
   FileWrite(handle, "ProviderId", "TotalTrades", "NetProfit", "ProfitFactor", 
             "MaxDrawdown", "WinRate", "IsActive", "LastUpdate");
   
   // Write provider data
   for(int i = 0; i < ArraySize(g_Providers); i++)
   {
      FileWrite(handle,
                g_Providers[i].providerId,
                g_Providers[i].totalTrades,
                DoubleToString(g_Providers[i].netProfit, 2),
                DoubleToString(g_Providers[i].profitFactor, 2),
                DoubleToString(g_Providers[i].maxDrawdown, 2),
                DoubleToString(g_Providers[i].winRate, 2),
                g_Providers[i].isActive ? "1" : "0",
                IntegerToString((int)g_Providers[i].lastUpdate));
   }
   
   FileClose(handle);
   
   Log(LOG_DEBUG, StringFormat("Saved %d provider stats to file", ArraySize(g_Providers)));
   return true;
}

//+------------------------------------------------------------------+
//| Load provider stats from CSV file                                |
//+------------------------------------------------------------------+
bool LoadProviderStatsFromFile()
{
   string providerFile = "SHRA_Providers_" + IntegerToString(AccountNumber()) + ".csv";
   
   if(!FileIsExist(providerFile))
   {
      Log(LOG_INFO, "No saved provider stats file found. Will build from history.");
      return false;
   }
   
   int handle = FileOpen(providerFile, FILE_READ|FILE_CSV|FILE_ANSI, ",");
   
   if(handle == INVALID_HANDLE)
   {
      Log(LOG_ERROR, StringFormat("Failed to load provider stats: %d", GetLastError()));
      return false;
   }
   
   // Skip header line
   string dummy = FileReadString(handle);
   
   // Clear existing array
   ArrayResize(g_Providers, 0);
   
   // Read provider data
   int count = 0;
   while(!FileIsEnding(handle))
   {
      ProviderStats stats;
      
      stats.providerId = FileReadString(handle);
      if(StringLen(stats.providerId) == 0) break;
      
      stats.totalTrades = (int)FileReadNumber(handle);
      stats.netProfit = FileReadNumber(handle);
      stats.profitFactor = FileReadNumber(handle);
      stats.maxDrawdown = FileReadNumber(handle);
      stats.winRate = FileReadNumber(handle);
      stats.isActive = ((int)FileReadNumber(handle) == 1);
      stats.lastUpdate = (datetime)FileReadNumber(handle);
      
      // Add to array
      int size = ArraySize(g_Providers);
      ArrayResize(g_Providers, size + 1);
      g_Providers[size] = stats;
      count++;
   }
   
   FileClose(handle);
   
   Log(LOG_INFO, StringFormat("Loaded %d provider stats from file", count));
   return true;
}

//+------------------------------------------------------------------+
//| Load persisted state from GlobalVariables                         |
//+------------------------------------------------------------------+
void LoadPersistedState()
{
   // Initialize variable names with account number
   g_PeakEquityVar = "SHRA_PeakEquity_" + IntegerToString(AccountNumber());
   g_KillSwitchVar = "SHRA_KillSwitch_" + IntegerToString(AccountNumber());
   g_EquityLockVar = "SHRA_EquityLock_" + IntegerToString(AccountNumber());
   g_EAStartTimeVar = "SHRA_StartTime_" + IntegerToString(AccountNumber());
   
   // 1. PEAK EQUITY
   if(GlobalVariableCheck(g_PeakEquityVar))
   {
      double savedPeak = GlobalVariableGet(g_PeakEquityVar);
      double currentEquity = AccountEquity();
      
      g_PeakEquity = MathMax(savedPeak, currentEquity);
      
      Log(LOG_INFO, StringFormat("Peak equity restored: %.2f (stored: %.2f, current: %.2f)",
          g_PeakEquity, savedPeak, currentEquity));
   }
   else
   {
      g_PeakEquity = AccountEquity();
      GlobalVariableSet(g_PeakEquityVar, g_PeakEquity);
      Log(LOG_INFO, StringFormat("Peak equity initialized: %.2f", g_PeakEquity));
   }
   
   // 2. KILL SWITCH STATUS
   g_TradingDisabled = false;
   if(GlobalVariableCheck(g_KillSwitchVar))
   {
      double flagValue = GlobalVariableGet(g_KillSwitchVar);
      if(flagValue > 0)
      {
         g_TradingDisabled = true;
         Log(LOG_ERROR, "Kill switch active from previous session. Trading disabled.");
         AppendToAuditLog("KILL_SWITCH_PERSIST", "Kill switch was active, trading remains disabled", 0);
      }
   }
   
   // 3. EQUITY LOCK LEVEL
   if(UseTrailingEquityLock && GlobalVariableCheck(g_EquityLockVar))
   {
      g_EquityLockLevel = GlobalVariableGet(g_EquityLockVar);
      Log(LOG_INFO, StringFormat("Equity lock level restored: %.2f", g_EquityLockLevel));
   }
   else
   {
      g_EquityLockLevel = 0.0;
   }
   
   // 4. EA START TIME
   if(GlobalVariableCheck(g_EAStartTimeVar))
   {
      g_EAStartTime = (datetime)GlobalVariableGet(g_EAStartTimeVar);
      Log(LOG_INFO, StringFormat("EA start time restored: %s (age: %d days)", 
          TimeToString(g_EAStartTime), (int)((TimeCurrent() - g_EAStartTime) / 86400)));
   }
   else
   {
      g_EAStartTime = TimeCurrent();
      GlobalVariableSet(g_EAStartTimeVar, (double)g_EAStartTime);
      Log(LOG_INFO, StringFormat("EA start time initialized: %s", TimeToString(g_EAStartTime)));
   }
   
   g_LastStateSave = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Save persisted state to GlobalVariables                          |
//+------------------------------------------------------------------+
void SavePersistedState()
{
   GlobalVariableSet(g_PeakEquityVar, g_PeakEquity);
   GlobalVariableSet(g_KillSwitchVar, g_TradingDisabled ? 1.0 : 0.0);
   GlobalVariableSet(g_EquityLockVar, g_EquityLockLevel);
   GlobalVariableSet(g_EAStartTimeVar, (double)g_EAStartTime);
   
   Log(LOG_DEBUG, "Critical state saved to GlobalVariables");
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
//| Calculate allowed exposure based on DD                           |
//+------------------------------------------------------------------+
double CalculateAllowedExposure(double currentDD)
{
   if(currentDD >= MaxPortfolioDDPercent)
   {
      return 0.0;
   }
   
   double allowedExposure = MaxPortfolioDDPercent * (1.0 - (currentDD / MaxPortfolioDDPercent));
   
   return allowedExposure;
}

//+------------------------------------------------------------------+
//| Identify provider from trade                                     |
//+------------------------------------------------------------------+
string IdentifyProvider(int magic, string comment)
{
   if(magic != 0)
   {
      return "Magic_" + IntegerToString(magic);
   }
   
   for(int i = 0; i < ArraySize(g_CommentTagsList); i++)
   {
      if(StringFind(comment, g_CommentTagsList[i]) >= 0)
      {
         return g_CommentTagsList[i];
      }
   }
   
   return "Manual";
}

//+------------------------------------------------------------------+
//| Calculate risk for a trade                                       |
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
      
      if(StringFind(trade.symbol, "JPY") >= 0)
      {
         pipSize *= 10;
      }
      
      double pips = slDistance / pipSize;
      double risk = pips * pointValue * trade.lots;
      
      return risk;
   }
   else
   {
      double equity = AccountEquity();
      double defaultRisk = equity * (MaxRiskNoSLPercentPerTrade / 100.0);
      return defaultRisk;
   }
}

//+------------------------------------------------------------------+
//| Check if trade should be managed                                 |
//+------------------------------------------------------------------+
bool ShouldManageTrade(int magic, string comment)
{
   if(ProviderFilterMode == FILTER_ALL_TRADES)
   {
      return true;
   }
   
   if(ProviderFilterMode == FILTER_ALL_NON_MANUAL)
   {
      return (magic != 0);
   }
   
   if(ProviderFilterMode == FILTER_MAGIC_LIST)
   {
      for(int i = 0; i < ArraySize(g_MagicNumbers); i++)
      {
         if(magic == g_MagicNumbers[i]) return true;
      }
      if(IncludeManualTrades && magic == 0) return true;
      return false;
   }
   
   if(ProviderFilterMode == FILTER_COMMENT_TAGS)
   {
      for(int i = 0; i < ArraySize(g_CommentTagsList); i++)
      {
         if(StringFind(comment, g_CommentTagsList[i]) >= 0) return true;
      }
      if(IncludeManualTrades && magic == 0) return true;
      return false;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Scan open orders and classify                                    |
//+------------------------------------------------------------------+
void ScanOpenOrders()
{
   ArrayResize(g_OpenTrades, 0);
   
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      
      if(OrderType() > OP_SELL) continue;
      
      if(!ShouldManageTrade(OrderMagicNumber(), OrderComment()))
      {
         continue;
      }
      
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
   
   Log(LOG_DEBUG, StringFormat("Scanned %d managed open trades", ArraySize(g_OpenTrades)));
}

//+------------------------------------------------------------------+
//| Calculate total portfolio exposure                               |
//+------------------------------------------------------------------+
double CalculateTotalExposure()
{
   double totalRisk = 0.0;
   double equity = AccountEquity();
   
   if(equity <= 0) return 0.0;
   
   for(int i = 0; i < ArraySize(g_OpenTrades); i++)
   {
      totalRisk += g_OpenTrades[i].riskAmount;
   }
   
   return (totalRisk / equity) * 100.0;
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
      Log(LOG_INFO, StringFormat("Closed order %d: %s", ticket, reason));
   }
   else
   {
      Log(LOG_ERROR, StringFormat("Failed to close order %d: %d", ticket, GetLastError()));
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Find worst performing trade                                      |
//+------------------------------------------------------------------+
int FindWorstTrade()
{
   if(ArraySize(g_OpenTrades) == 0) return -1;
   
   int worstIndex = 0;
   double worstPL = g_OpenTrades[0].floatingPL;
   
   for(int i = 1; i < ArraySize(g_OpenTrades); i++)
   {
      if(g_OpenTrades[i].floatingPL < worstPL)
      {
         worstPL = g_OpenTrades[i].floatingPL;
         worstIndex = i;
      }
   }
   
   return worstIndex;
}

//+------------------------------------------------------------------+
//| Handle exposure breach                                           |
//+------------------------------------------------------------------+
void HandleExposureBreach(double currentExposure, double allowedExposure)
{
   AppendToAuditLog("EXPOSURE_BREACH",
                    StringFormat("Exposure %.2f%% exceeds allowed %.2f%%", currentExposure, allowedExposure),
                    currentExposure);
   
   if(RiskReductionMode == RISK_CLOSE_WORST_FIRST)
   {
      while(CalculateTotalExposure() > allowedExposure && ArraySize(g_OpenTrades) > 0)
      {
         int worstIndex = FindWorstTrade();
         if(worstIndex >= 0)
         {
            CloseOrder(g_OpenTrades[worstIndex].ticket, "Exposure breach");
            ScanOpenOrders();
         }
         else
         {
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Enhanced ActivateKillSwitch with persistence                     |
//+------------------------------------------------------------------+
void ActivateKillSwitch()
{
   Log(LOG_ERROR, "=== KILL SWITCH ACTIVATED ===");
   
   double currentDD = CalculateCurrentDrawdown();
   
   AppendToAuditLog("KILL_SWITCH", 
                    StringFormat("Emergency stop triggered. DD: %.2f%%, Open trades: %d", 
                                 currentDD, ArraySize(g_OpenTrades)),
                    AccountEquity());
   
   int closedCount = 0;
   for(int i = ArraySize(g_OpenTrades) - 1; i >= 0; i--)
   {
      if(CloseOrder(g_OpenTrades[i].ticket, "Kill switch"))
      {
         closedCount++;
      }
   }
   
   GlobalVariableSet(g_KillSwitchVar, 1.0);
   g_TradingDisabled = true;
   
   SaveProviderStatsToFile();
   
   Log(LOG_ERROR, StringFormat("Kill switch activated: %d trades closed. Trading disabled.", closedCount));
   
   Alert("SignalHarvesterRiskManager: KILL SWITCH ACTIVATED! Trading disabled.");
}

//+------------------------------------------------------------------+
//| Enhanced UpdatePeakEquity with persistence                        |
//+------------------------------------------------------------------+
void UpdatePeakEquity()
{
   double currentEquity = AccountEquity();
   
   if(DDLookbackMode == DD_PEAK_SINCE_START)
   {
      if(currentEquity > g_PeakEquity)
      {
         double oldPeak = g_PeakEquity;
         g_PeakEquity = currentEquity;
         
         GlobalVariableSet(g_PeakEquityVar, g_PeakEquity);
         
         AppendToAuditLog("PEAK_EQUITY_UPDATE", 
                          StringFormat("Peak increased from %.2f to %.2f", oldPeak, g_PeakEquity),
                          g_PeakEquity);
         
         Log(LOG_DEBUG, StringFormat("New peak equity: %.2f (persisted)", g_PeakEquity));
      }
   }
}

//+------------------------------------------------------------------+
//| Enhanced CheckTrailingEquityLock with persistence                |
//+------------------------------------------------------------------+
void CheckTrailingEquityLock()
{
   double equity = AccountEquity();
   double balance = AccountBalance();
   double gain = equity - balance;
   double gainPercent = (balance > 0) ? ((gain / balance) * 100.0) : 0.0;
   
   if(gainPercent >= TrailingEquityLockTriggerPercent)
   {
      double lockLevel = balance + (gain * (TrailingEquityLockPercent / 100.0));
      
      if(lockLevel > g_EquityLockLevel)
      {
         double oldLock = g_EquityLockLevel;
         g_EquityLockLevel = lockLevel;
         
         GlobalVariableSet(g_EquityLockVar, g_EquityLockLevel);
         
         AppendToAuditLog("EQUITY_LOCK_UPDATE",
                          StringFormat("Lock raised from %.2f to %.2f (Gain: %.2f%%)", 
                                       oldLock, g_EquityLockLevel, gainPercent),
                          g_EquityLockLevel);
         
         Log(LOG_INFO, StringFormat("Trailing equity lock updated: %.2f (persisted)", g_EquityLockLevel));
      }
      
      if(equity < g_EquityLockLevel)
      {
         Log(LOG_ERROR, StringFormat("Equity lock triggered: %.2f < %.2f", equity, g_EquityLockLevel));
         
         AppendToAuditLog("EQUITY_LOCK_BREACH",
                          StringFormat("Equity %.2f dropped below lock %.2f", equity, g_EquityLockLevel),
                          equity);
         
         ActivateKillSwitch();
      }
   }
}

//+------------------------------------------------------------------+
//| Update provider stats from history (placeholder)                 |
//+------------------------------------------------------------------+
void UpdateProviderStatsFromHistory()
{
   Log(LOG_DEBUG, "Provider stats updated from history");
}

//+------------------------------------------------------------------+
//| Enforce global caps (placeholder)                                |
//+------------------------------------------------------------------+
void EnforceGlobalCaps()
{
   if(ArraySize(g_OpenTrades) > GlobalMaxOpenTrades)
   {
      Log(LOG_ERROR, StringFormat("Global max trades exceeded: %d > %d", 
          ArraySize(g_OpenTrades), GlobalMaxOpenTrades));
   }
}

//+------------------------------------------------------------------+
//| Enforce symbol caps (placeholder)                                |
//+------------------------------------------------------------------+
void EnforceSymbolCaps()
{
   // Implementation: Check per-symbol exposure
}

//+------------------------------------------------------------------+
//| Enforce provider caps (placeholder)                              |
//+------------------------------------------------------------------+
void EnforceProviderCaps()
{
   // Implementation: Check per-provider exposure
}

//+------------------------------------------------------------------+
//| Enforce time stops (placeholder)                                 |
//+------------------------------------------------------------------+
void EnforceTimeStops()
{
   // Implementation: Close trades older than MaxTradeAgeMinutes
}

//+------------------------------------------------------------------+
//| Apply auto SL/TP (placeholder)                                   |
//+------------------------------------------------------------------+
void ApplyAutoSLTP()
{
   // Implementation: Set SL/TP on trades without them
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Log(LOG_INFO, "=== SignalHarvesterRiskManager v2.0 Starting (WITH PERSISTENCE) ===");
   
   LoadPersistedState();
   ParseMagicList();
   ParseCommentTags();
   LoadProviderStatsFromFile();
   SaveConfigurationSnapshot();
   
   Log(LOG_INFO, StringFormat("State loaded: Peak=%.2f, KillSwitch=%s, Providers=%d",
       g_PeakEquity, g_TradingDisabled ? "ACTIVE" : "OFF", ArraySize(g_Providers)));
   Log(LOG_INFO, StringFormat("MaxPortfolioDDPercent: %.2f%%, EquityStopDDPercent: %.2f%%", 
       MaxPortfolioDDPercent, EquityStopDDPercent));
   
   AppendToAuditLog("EA_START", "EA initialized successfully", AccountEquity());
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Log(LOG_INFO, StringFormat("=== SignalHarvesterRiskManager EA Stopped (Reason: %d) ===", reason));
   
   SavePersistedState();
   SaveProviderStatsToFile();
   
   AppendToAuditLog("EA_STOP", StringFormat("EA deinitialized. Reason: %d", reason), AccountEquity());
   
   Log(LOG_INFO, "All state saved successfully");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_TradingDisabled)
   {
      return;
   }
   
   UpdatePeakEquity();
   
   double currentDD = CalculateCurrentDrawdown();
   
   if(UseEquityStop && currentDD >= EquityStopDDPercent)
   {
      Log(LOG_ERROR, StringFormat("EQUITY STOP TRIGGERED! DD: %.2f%% >= %.2f%%", 
          currentDD, EquityStopDDPercent));
      ActivateKillSwitch();
      return;
   }
   
   if(UseTrailingEquityLock)
   {
      CheckTrailingEquityLock();
   }
   
   if(TimeCurrent() - g_LastHistoryScan >= HistoryScanIntervalSeconds)
   {
      UpdateProviderStatsFromHistory();
      g_LastHistoryScan = TimeCurrent();
   }
   
   ScanOpenOrders();
   
   if(UseTimeStop)
   {
      EnforceTimeStops();
   }
   
   double totalExposure = CalculateTotalExposure();
   double allowedExposure = CalculateAllowedExposure(currentDD);
   
   if(TestMode)
   {
      static datetime lastPrint = 0;
      if(TimeCurrent() - lastPrint >= 10)
      {
         Log(LOG_INFO, StringFormat("TEST MODE | Equity: %.2f | Peak: %.2f | DD: %.2f%% | Exposure: %.2f%% | Allowed: %.2f%%",
             AccountEquity(), g_PeakEquity, currentDD, totalExposure, allowedExposure));
         lastPrint = TimeCurrent();
      }
   }
   
   if(totalExposure > allowedExposure)
   {
      Log(LOG_ERROR, StringFormat("EXPOSURE BREACH! Total: %.2f%% > Allowed: %.2f%%", 
          totalExposure, allowedExposure));
      HandleExposureBreach(totalExposure, allowedExposure);
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
      
      Log(LOG_DEBUG, "Periodic state save completed");
   }
}

//+------------------------------------------------------------------+