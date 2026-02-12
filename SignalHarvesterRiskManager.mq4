//+------------------------------------------------------------------+
//|                                   SignalHarvesterRiskManager.mq4 |
//|                        Copyright 2026, Senior MQL4 Engineer      |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "1.00"
#property strict

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
   RISK_BLOCK_NEW_TRADES,    // Only block new trades from being kept
   RISK_CLOSE_WORST_FIRST,   // Close worst trades (most negative P/L)
   RISK_PRORATA_TRIM         // Close positions proportionally
};

enum ENUM_AUTO_SL_MODE
{
   AUTO_SL_NONE,             // No automatic stop loss
   AUTO_SL_ATR,              // ATR-based stop loss
   AUTO_SL_FIXED_PIPS,       // Fixed pips stop loss
   AUTO_SL_STRUCTURE         // Recent swing structure (simple High/Low)
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
input double MaxPortfolioDDPercent = 20.0;              // Maximum portfolio drawdown budget (%)
input ENUM_DD_LOOKBACK_MODE DDLookbackMode = DD_PEAK_SINCE_START; // Drawdown lookback mode
input int    RollingHours = 168;                        // Rolling hours for DD calculation (if rolling mode)
input double MaxRiskNoSLPercentPerTrade = 2.0;          // Risk per trade with no SL (% of equity)
input int    DefaultStopLossPips = 100;                 // Default SL in pips if none set

// === PROVIDER FILTERING ===
input bool   IncludeManualTrades = false;               // Include manual trades (magic=0)?
input ENUM_PROVIDER_FILTER_MODE ProviderFilterMode = FILTER_MAGIC_LIST; // Provider filter mode
input string MagicList = "12345,67890,11111";           // CSV list of magic numbers
input string CommentTags = "SignalStart,Provider1,Provider2"; // CSV comment substrings

// === PROVIDER PERFORMANCE / HARVESTING ===
input int    MaxConcurrentProviders = 5;                // Max active providers at once
input int    ProviderScoreWindowTrades = 20;            // Last N closed trades for provider scoring
input int    ProviderMinTradesToQualify = 5;            // Min trades to qualify provider
input double ProviderProfitThreshold = 0.0;             // Min net profit in window (account currency)
input double ProviderMaxDDThreshold = 10.0;             // Max provider drawdown in window (%)
input bool   CloseInactiveProviderOpenTrades = true;    // Close open trades from inactive providers?

// === RISK CAPS ===
input int    GlobalMaxOpenTrades = 20;                  // Max open trades across account
input double GlobalMaxOpenLots = 10.0;                  // Max open lots across account
input double MaxSymbolExposurePercent = 5.0;            // Max exposure per symbol (% equity)
input double MaxProviderExposurePercent = 10.0;         // Max exposure per provider (% equity)

// === EMERGENCY CONTROLS ===
input bool   EmergencyKillSwitch = true;                // Emergency kill all on breach?
input ENUM_RISK_REDUCTION_MODE RiskReductionMode = RISK_CLOSE_WORST_FIRST; // Risk reduction mode
input double TrimStepPercent = 10.0;                    // Trim step % when reducing exposure

// === EQUITY & TIME STOPS ===
input bool   UseEquityStop = true;                      // Use hard equity stop?
input double EquityStopDDPercent = 25.0;                // Hard equity stop DD % (kill all)
input bool   UseTimeStop = false;                       // Close trades older than max age?
input int    MaxTradeAgeMinutes = 1440;                 // Max trade age in minutes (24h default)

// === TRAILING EQUITY LOCK ===
input bool   UseTrailingEquityLock = false;             // Lock in profits after gain?
input double TrailingEquityLockTriggerPercent = 10.0;   // Trigger % gain
input double TrailingEquityLockPercent = 50.0;          // Lock % of gains

// === AUTO SL/TP ===
input ENUM_AUTO_SL_MODE AutoSLMode = AUTO_SL_FIXED_PIPS; // Auto SL mode
input int    ATRPeriod = 14;                            // ATR period
input double ATRMultiplier = 2.0;                       // ATR multiplier for SL
input int    FixedSLPips = 50;                          // Fixed SL in pips
input int    MaxAllowedSLPips = 200;                    // Max allowed SL distance (pips)
input double AutoTPRiskRewardRatio = 2.0;               // Auto TP as RR multiple of SL

// === LOGGING & MISC ===
input ENUM_LOG_LEVEL LogLevel = LOG_INFO;               // Logging level
input int    HistoryScanIntervalSeconds = 60;           // Throttle history scan interval
input bool   TestMode = false;                          // Test mode: print exposure stats

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
double g_PeakEquity = 0.0;
datetime g_LastHistoryScan = 0;
datetime g_EAStartTime = 0;
bool g_TradingDisabled = false;
double g_EquityLockLevel = 0.0;
string g_KillSwitchFlag = "EA_KILL_SWITCH";

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
   double   riskAmount;      // Computed risk in account currency
   double   floatingPL;
};

TradeInfo g_OpenTrades[];

// Parsed input lists
int g_MagicNumbers[];
string g_CommentTagsList[];

//+------------------------------------------------------------------+
//| FUNCTION DECLARATIONS                                            |
//+------------------------------------------------------------------+
void Log(ENUM_LOG_LEVEL level, string message);
void ParseMagicList();
void ParseCommentTags();
void UpdatePeakEquity();
double CalculateCurrentDrawdown();
void ActivateKillSwitch();
void CheckTrailingEquityLock();
void UpdateProviderStatsFromHistory();
void ScanOpenOrders();
bool ShouldManageTrade(int ticket);
string GetProviderIdFromOrder();
double CalculateTradeRisk(int ticket);
void EnforceTimeStops();
double CalculateTotalExposure();
double CalculateAllowedExposure(double currentDD);
void HandleExposureBreach(double totalExposure, double allowedExposure);
void CloseWorstTrades(double excessExposure);
void TrimPositionsProRata(double trimPercent);
void EnforceGlobalCaps();
void EnforceSymbolCaps();
void EnforceProviderCaps();
void ApplyAutoSLTP();
double CalculateAutoSL(TradeInfo &trade);
double CalculateAutoTP(TradeInfo &trade, double sl);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Log(LOG_INFO, "=== SignalHarvesterRiskManager EA Starting ===");
   
   g_EAStartTime = TimeCurrent();
   g_PeakEquity = AccountEquity();
   g_TradingDisabled = false;
   g_EquityLockLevel = 0.0;
   
   // Check for kill switch flag from previous run
   if(GlobalVariableCheck(g_KillSwitchFlag))
   {
      double flagValue = GlobalVariableGet(g_KillSwitchFlag);
      if(flagValue > 0)
      {
         g_TradingDisabled = true;
         Log(LOG_ERROR, "Kill switch active from previous session. Trading disabled.");
      }
   }
   
   // Parse input lists
   ParseMagicList();
   ParseCommentTags();
   
   Log(LOG_INFO, StringFormat("MaxPortfolioDDPercent: %.2f%%, EquityStopDDPercent: %.2f%%", 
       MaxPortfolioDDPercent, EquityStopDDPercent));
   Log(LOG_INFO, StringFormat("Provider filter mode: %d, Max concurrent providers: %d", 
       ProviderFilterMode, MaxConcurrentProviders));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Log(LOG_INFO, StringFormat("=== SignalHarvesterRiskManager EA Stopped (Reason: %d) ===", reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if trading is disabled
   if(g_TradingDisabled)
   {
      return;
   }
   
   // Update peak equity for drawdown calculation
   UpdatePeakEquity();
   
   // Calculate current drawdown
   double currentDD = CalculateCurrentDrawdown();
   
   // Check equity stop
   if(UseEquityStop && currentDD >= EquityStopDDPercent)
   {
      Log(LOG_ERROR, StringFormat("EQUITY STOP TRIGGERED! Current DD: %.2f%% >= %.2f%%", 
          currentDD, EquityStopDDPercent));
      ActivateKillSwitch();
      return;
   }
   
   // Check trailing equity lock
   if(UseTrailingEquityLock)
   {
      CheckTrailingEquityLock();
   }
   
   // Throttled history scan for provider stats
   if(TimeCurrent() - g_LastHistoryScan >= HistoryScanIntervalSeconds)
   {
      UpdateProviderStatsFromHistory();
      g_LastHistoryScan = TimeCurrent();
   }
   
   // Scan and classify all open orders
   ScanOpenOrders();
   
   // Enforce time stops
   if(UseTimeStop)
   {
      EnforceTimeStops();
   }
   
   // Calculate total exposure
   double totalExposure = CalculateTotalExposure();
   double allowedExposure = CalculateAllowedExposure(currentDD);
   
   // Test mode output
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
   
   // Enforce portfolio exposure cap
   if(totalExposure > allowedExposure)
   {
      Log(LOG_ERROR, StringFormat("EXPOSURE BREACH! Total: %.2f%% > Allowed: %.2f%%", 
          totalExposure, allowedExposure));
      HandleExposureBreach(totalExposure, allowedExposure);
   }
   
   // Enforce other caps (trade count, lots, per-symbol, per-provider)
   EnforceGlobalCaps();
   EnforceSymbolCaps();
   EnforceProviderCaps();
   
   // Manage auto SL/TP on existing trades
   ApplyAutoSLTP();
}

//+------------------------------------------------------------------+
//| Logging function                                                  |
//+------------------------------------------------------------------+
void Log(ENUM_LOG_LEVEL level, string message)
{
   if(level > LogLevel) return;
   
   string prefix = "";
   switch(level)
   {
      case LOG_ERROR: prefix = "[ERROR] "; break;
      case LOG_INFO:  prefix = "[INFO] ";  break;
      case LOG_DEBUG: prefix = "[DEBUG] "; break;
   }
   
   Print(prefix + message);
}

//+------------------------------------------------------------------+
//| Parse magic number list from CSV input                           |
//+------------------------------------------------------------------+
void ParseMagicList()
{
   ArrayResize(g_MagicNumbers, 0);
   
   if(StringLen(MagicList) == 0) return;
   
   string items[];
   int count = StringSplit(MagicList, ',', items);
   
   for(int i = 0; i < count; i++)
   {
      string trimmed = StringTrimLeft(StringTrimRight(items[i]));
      int magic = (int)StringToInteger(trimmed);
      if(magic > 0)
      {
         int size = ArraySize(g_MagicNumbers);
         ArrayResize(g_MagicNumbers, size + 1);
         g_MagicNumbers[size] = magic;
      }
   }
   
   Log(LOG_INFO, StringFormat("Parsed %d magic numbers from MagicList", ArraySize(g_MagicNumbers)));
}

//+------------------------------------------------------------------+
//| Parse comment tags from CSV input                                |
//+------------------------------------------------------------------+
void ParseCommentTags()
{
   ArrayResize(g_CommentTagsList, 0);
   
   if(StringLen(CommentTags) == 0) return;
   
   string items[];
   int count = StringSplit(CommentTags, ',', items);
   
   for(int i = 0; i < count; i++)
   {
      string trimmed = StringTrimLeft(StringTrimRight(items[i]));
      if(StringLen(trimmed) > 0)
      {
         int size = ArraySize(g_CommentTagsList);
         ArrayResize(g_CommentTagsList, size + 1);
         g_CommentTagsList[size] = trimmed;
      }
   }
   
   Log(LOG_INFO, StringFormat("Parsed %d comment tags from CommentTags", ArraySize(g_CommentTagsList)));
}

//+------------------------------------------------------------------+
//| Update peak equity for drawdown calculation                      |
//+------------------------------------------------------------------+
void UpdatePeakEquity()
{
   double currentEquity = AccountEquity();
   
   if(DDLookbackMode == DD_PEAK_SINCE_START)
   {
      if(currentEquity > g_PeakEquity)
      {
         g_PeakEquity = currentEquity;
      }
   }
   else if(DDLookbackMode == DD_PEAK_ROLLING_HOURS)
   {
      // For rolling hours, we would need to track equity history
      // Simplified: use current equity if higher
      if(currentEquity > g_PeakEquity)
      {
         g_PeakEquity = currentEquity;
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate current drawdown percentage                            |
//+------------------------------------------------------------------+
double CalculateCurrentDrawdown()
{
   if(g_PeakEquity <= 0) return 0.0;
   
   double currentEquity = AccountEquity();
   double dd = ((g_PeakEquity - currentEquity) / g_PeakEquity) * 100.0;
   
   return MathMax(0.0, dd);
}

//+------------------------------------------------------------------+
//| Activate kill switch and close all trades                        |
//+------------------------------------------------------------------+
void ActivateKillSwitch()
{
   if(!EmergencyKillSwitch)
   {
      Log(LOG_ERROR, "Kill switch disabled in settings. Trading halted but no close action.");
      g_TradingDisabled = true;
      return;
   }
   
   Log(LOG_ERROR, "ACTIVATING KILL SWITCH - CLOSING ALL TRADES");
   g_TradingDisabled = true;
   
   // Set global variable flag
   GlobalVariableSet(g_KillSwitchFlag, 1.0);
   
   // Close all managed trades
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      
      if(ShouldManageTrade(OrderTicket()))
      {
         bool closed = false;
         if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         {
            double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
            closed = OrderClose(OrderTicket(), OrderLots(), closePrice, 3, clrRed);
         }
         else
         {
            closed = OrderDelete(OrderTicket());
         }
         
         if(closed)
         {
            Log(LOG_INFO, StringFormat("Closed order #%d via kill switch", OrderTicket()));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check and update trailing equity lock                            |
//+------------------------------------------------------------------+
void CheckTrailingEquityLock()
{
   double currentEquity = AccountEquity();
   double startEquity = AccountBalance(); // Simplified - could track initial balance
   
   if(startEquity <= 0) return;
   
   double gainPercent = ((currentEquity - startEquity) / startEquity) * 100.0;
   
   if(gainPercent >= TrailingEquityLockTriggerPercent)
   {
      double lockLevel = startEquity + (currentEquity - startEquity) * (TrailingEquityLockPercent / 100.0);
      
      if(lockLevel > g_EquityLockLevel)
      {
         g_EquityLockLevel = lockLevel;
         Log(LOG_INFO, StringFormat("Trailing equity lock updated to %.2f", g_EquityLockLevel));
      }
      
      // Check if equity dropped below lock level
      if(g_EquityLockLevel > 0 && currentEquity < g_EquityLockLevel)
      {
         Log(LOG_ERROR, StringFormat("Equity lock breach! Current: %.2f < Lock: %.2f", 
             currentEquity, g_EquityLockLevel));
         ActivateKillSwitch();
      }
   }
}

//+------------------------------------------------------------------+
//| Update provider statistics from closed trade history             |
//+------------------------------------------------------------------+
void UpdateProviderStatsFromHistory()
{
   // This is a simplified placeholder implementation
   // Full implementation would analyze closed trades and update g_Providers array
   Log(LOG_DEBUG, "Updating provider stats from history");
}

//+------------------------------------------------------------------+
//| Scan all open orders and populate trades array                   |
//+------------------------------------------------------------------+
void ScanOpenOrders()
{
   ArrayResize(g_OpenTrades, 0);
   
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      
      if(!ShouldManageTrade(OrderTicket())) continue;
      
      int size = ArraySize(g_OpenTrades);
      ArrayResize(g_OpenTrades, size + 1);
      
      g_OpenTrades[size].ticket = OrderTicket();
      g_OpenTrades[size].providerId = GetProviderIdFromOrder();
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
      g_OpenTrades[size].riskAmount = CalculateTradeRisk(OrderTicket());
   }
}

//+------------------------------------------------------------------+
//| Check if trade should be managed by this EA                      |
//+------------------------------------------------------------------+
bool ShouldManageTrade(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return false;
   
   int magic = OrderMagicNumber();
   
   switch(ProviderFilterMode)
   {
      case FILTER_MAGIC_LIST:
         for(int i = 0; i < ArraySize(g_MagicNumbers); i++)
         {
            if(magic == g_MagicNumbers[i]) return true;
         }
         return false;
         
      case FILTER_COMMENT_TAGS:
         for(int i = 0; i < ArraySize(g_CommentTagsList); i++)
         {
            if(StringFind(OrderComment(), g_CommentTagsList[i]) >= 0) return true;
         }
         return false;
         
      case FILTER_ALL_NON_MANUAL:
         return (magic != 0);
         
      case FILTER_ALL_TRADES:
         return (magic != 0 || IncludeManualTrades);
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Get provider ID from order                                       |
//+------------------------------------------------------------------+
string GetProviderIdFromOrder()
{
   // Use magic number as provider ID
   return IntegerToString(OrderMagicNumber());
}

//+------------------------------------------------------------------+
//| Calculate risk amount for a trade                                |
//+------------------------------------------------------------------+
double CalculateTradeRisk(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return 0.0;
   
   double sl = OrderStopLoss();
   
   if(sl <= 0)
   {
      // No SL set - use default risk
      return AccountEquity() * (MaxRiskNoSLPercentPerTrade / 100.0);
   }
   
   double pips = 0;
   if(OrderType() == OP_BUY)
   {
      pips = (OrderOpenPrice() - sl) / Point;
   }
   else if(OrderType() == OP_SELL)
   {
      pips = (sl - OrderOpenPrice()) / Point;
   }
   
   double pipValue = MarketInfo(OrderSymbol(), MODE_TICKVALUE);
   return MathAbs(pips * pipValue * OrderLots());
}

//+------------------------------------------------------------------+
//| Enforce time stops on old trades                                 |
//+------------------------------------------------------------------+
void EnforceTimeStops()
{
   datetime currentTime = TimeCurrent();
   
   for(int i = 0; i < ArraySize(g_OpenTrades); i++)
   {
      int ageMinutes = (int)((currentTime - g_OpenTrades[i].openTime) / 60);
      
      if(ageMinutes >= MaxTradeAgeMinutes)
      {
         if(OrderSelect(g_OpenTrades[i].ticket, SELECT_BY_TICKET))
         {
            double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
            if(OrderClose(OrderTicket(), OrderLots(), closePrice, 3, clrOrange))
            {
               Log(LOG_INFO, StringFormat("Closed old trade #%d (age: %d min)", 
                   g_OpenTrades[i].ticket, ageMinutes));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate total portfolio exposure                               |
//+------------------------------------------------------------------+
double CalculateTotalExposure()
{
   double totalRisk = 0.0;
   
   for(int i = 0; i < ArraySize(g_OpenTrades); i++)
   {
      totalRisk += g_OpenTrades[i].riskAmount;
   }
   
   double equity = AccountEquity();
   if(equity <= 0) return 0.0;
   
   return (totalRisk / equity) * 100.0;
}

//+------------------------------------------------------------------+
//| Calculate allowed exposure based on current drawdown             |
//+------------------------------------------------------------------+
double CalculateAllowedExposure(double currentDD)
{
   double remaining = MaxPortfolioDDPercent - currentDD;
   return MathMax(0.0, remaining);
}

//+------------------------------------------------------------------+
//| Handle exposure breach                                           |
//+------------------------------------------------------------------+
void HandleExposureBreach(double totalExposure, double allowedExposure)
{
   switch(RiskReductionMode)
   {
      case RISK_BLOCK_NEW_TRADES:
         g_TradingDisabled = true;
         Log(LOG_ERROR, "Trading disabled due to exposure breach");
         break;
         
      case RISK_CLOSE_WORST_FIRST:
         CloseWorstTrades(totalExposure - allowedExposure);
         break;
         
      case RISK_PRORATA_TRIM:
         TrimPositionsProRata(TrimStepPercent);
         break;
   }
}

//+------------------------------------------------------------------+
//| Close worst performing trades                                    |
//+------------------------------------------------------------------+
void CloseWorstTrades(double excessExposure)
{
   // Sort trades by P/L (worst first)
   for(int i = 0; i < ArraySize(g_OpenTrades) - 1; i++)
   {
      for(int j = i + 1; j < ArraySize(g_OpenTrades); j++)
      {
         if(g_OpenTrades[j].floatingPL < g_OpenTrades[i].floatingPL)
         {
            TradeInfo temp = g_OpenTrades[i];
            g_OpenTrades[i] = g_OpenTrades[j];
            g_OpenTrades[j] = temp;
         }
      }
   }
   
   double reducedExposure = 0.0;
   
   for(int i = 0; i < ArraySize(g_OpenTrades); i++)
   {
      if(reducedExposure >= excessExposure) break;
      
      if(OrderSelect(g_OpenTrades[i].ticket, SELECT_BY_TICKET))
      {
         double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
         if(OrderClose(OrderTicket(), OrderLots(), closePrice, 3, clrRed))
         {
            reducedExposure += g_OpenTrades[i].riskAmount;
            Log(LOG_INFO, StringFormat("Closed worst trade #%d (P/L: %.2f)", 
                g_OpenTrades[i].ticket, g_OpenTrades[i].floatingPL));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trim all positions proportionally                                |
//+------------------------------------------------------------------+
void TrimPositionsProRata(double trimPercent)
{
   for(int i = 0; i < ArraySize(g_OpenTrades); i++)
   {
      if(OrderSelect(g_OpenTrades[i].ticket, SELECT_BY_TICKET))
      {
         double currentLots = OrderLots();
         double trimLots = currentLots * (trimPercent / 100.0);
         trimLots = NormalizeDouble(trimLots, 2);
         
         if(trimLots >= MarketInfo(OrderSymbol(), MODE_MINLOT))
         {
            double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
            if(OrderClose(OrderTicket(), trimLots, closePrice, 3, clrOrange))
            {
               Log(LOG_INFO, StringFormat("Trimmed %.2f lots from trade #%d", 
                   trimLots, g_OpenTrades[i].ticket));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Enforce global trade count and lot caps                          |
//+------------------------------------------------------------------+
void EnforceGlobalCaps()
{
   int tradeCount = ArraySize(g_OpenTrades);
   double totalLots = 0.0;
   
   for(int i = 0; i < tradeCount; i++)
   {
      totalLots += g_OpenTrades[i].lots;
   }
   
   if(tradeCount > GlobalMaxOpenTrades)
   {
      Log(LOG_ERROR, StringFormat("Trade count cap exceeded: %d > %d", 
          tradeCount, GlobalMaxOpenTrades));
      CloseWorstTrades(0); // Close worst trade
   }
   
   if(totalLots > GlobalMaxOpenLots)
   {
      Log(LOG_ERROR, StringFormat("Total lots cap exceeded: %.2f > %.2f", 
          totalLots, GlobalMaxOpenLots));
      TrimPositionsProRata(TrimStepPercent);
   }
}

//+------------------------------------------------------------------+
//| Enforce per-symbol exposure caps                                 |
//+------------------------------------------------------------------+
void EnforceSymbolCaps()
{
   string symbols[];
   double exposure[];
   int symbolCount = 0;
   
   // Calculate exposure per symbol
   for(int i = 0; i < ArraySize(g_OpenTrades); i++)
   {
      bool found = false;
      int index = 0;
      
      for(int j = 0; j < symbolCount; j++)
      {
         if(symbols[j] == g_OpenTrades[i].symbol)
         {
            found = true;
            index = j;
            break;
         }
      }
      
      if(!found)
      {
         ArrayResize(symbols, symbolCount + 1);
         ArrayResize(exposure, symbolCount + 1);
         symbols[symbolCount] = g_OpenTrades[i].symbol;
         index = symbolCount;
         symbolCount++;
      }
      
      exposure[index] += g_OpenTrades[i].riskAmount;
   }
   
   // Check caps
   double equity = AccountEquity();
   for(int i = 0; i < symbolCount; i++)
   {
      double exposurePercent = (exposure[i] / equity) * 100.0;
      
      if(exposurePercent > MaxSymbolExposurePercent)
      {
         Log(LOG_ERROR, StringFormat("Symbol %s exposure %.2f%% exceeds limit %.2f%%", 
             symbols[i], exposurePercent, MaxSymbolExposurePercent));
      }
   }
}

//+------------------------------------------------------------------+
//| Enforce per-provider exposure caps                               |
//+------------------------------------------------------------------+
void EnforceProviderCaps()
{
   string providers[];
   double exposure[];
   int providerCount = 0;
   
   // Calculate exposure per provider
   for(int i = 0; i < ArraySize(g_OpenTrades); i++)
   {
      bool found = false;
      int index = 0;
      
      for(int j = 0; j < providerCount; j++)
      {
         if(providers[j] == g_OpenTrades[i].providerId)
         {
            found = true;
            index = j;
            break;
         }
      }
      
      if(!found)
      {
         ArrayResize(providers, providerCount + 1);
         ArrayResize(exposure, providerCount + 1);
         providers[providerCount] = g_OpenTrades[i].providerId;
         index = providerCount;
         providerCount++;
      }
      
      exposure[index] += g_OpenTrades[i].riskAmount;
   }
   
   // Check caps
   double equity = AccountEquity();
   for(int i = 0; i < providerCount; i++)
   {
      double exposurePercent = (exposure[i] / equity) * 100.0;
      
      if(exposurePercent > MaxProviderExposurePercent)
      {
         Log(LOG_ERROR, StringFormat("Provider %s exposure %.2f%% exceeds limit %.2f%%", 
             providers[i], exposurePercent, MaxProviderExposurePercent));
      }
   }
   
   // Check provider count
   if(providerCount > MaxConcurrentProviders)
   {
      Log(LOG_ERROR, StringFormat("Active provider count %d exceeds limit %d", 
          providerCount, MaxConcurrentProviders));
   }
}

//+------------------------------------------------------------------+
//| Apply automatic SL/TP to trades                                  |
//+------------------------------------------------------------------+
void ApplyAutoSLTP()
{
   for(int i = 0; i < ArraySize(g_OpenTrades); i++)
   {
      if(!OrderSelect(g_OpenTrades[i].ticket, SELECT_BY_TICKET)) continue;
      
      // Skip if SL already set and we're not overriding
      if(OrderStopLoss() > 0 && AutoSLMode == AUTO_SL_NONE) continue;
      
      double newSL = CalculateAutoSL(g_OpenTrades[i]);
      double newTP = CalculateAutoTP(g_OpenTrades[i], newSL);
      
      if(newSL > 0 && (OrderStopLoss() == 0 || MathAbs(OrderStopLoss() - newSL) > Point))
      {
         if(OrderModify(OrderTicket(), OrderOpenPrice(), newSL, newTP, 0, clrBlue))
         {
            Log(LOG_DEBUG, StringFormat("Updated SL/TP for order #%d", OrderTicket()));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate automatic stop loss                                    |
//+------------------------------------------------------------------+
double CalculateAutoSL(TradeInfo &trade)
{
   if(AutoSLMode == AUTO_SL_NONE) return 0.0;
   
   double sl = 0.0;
   
   switch(AutoSLMode)
   {
      case AUTO_SL_FIXED_PIPS:
         {
            double pips = FixedSLPips * Point;
            if(trade.orderType == OP_BUY)
               sl = trade.openPrice - pips;
            else if(trade.orderType == OP_SELL)
               sl = trade.openPrice + pips;
         }
         break;
         
      case AUTO_SL_ATR:
         {
            double atr = iATR(trade.symbol, 0, ATRPeriod, 0);
            double distance = atr * ATRMultiplier;
            if(trade.orderType == OP_BUY)
               sl = trade.openPrice - distance;
            else if(trade.orderType == OP_SELL)
               sl = trade.openPrice + distance;
         }
         break;
         
      case AUTO_SL_STRUCTURE:
         {
            // Simple structure-based SL using recent highs/lows
            if(trade.orderType == OP_BUY)
               sl = iLow(trade.symbol, 0, iLowest(trade.symbol, 0, MODE_LOW, 20, 1));
            else if(trade.orderType == OP_SELL)
               sl = iHigh(trade.symbol, 0, iHighest(trade.symbol, 0, MODE_HIGH, 20, 1));
         }
         break;
   }
   
   // Verify SL is within max allowed distance
   double slPips = MathAbs(trade.openPrice - sl) / Point;
   if(slPips > MaxAllowedSLPips)
   {
      double maxDistance = MaxAllowedSLPips * Point;
      if(trade.orderType == OP_BUY)
         sl = trade.openPrice - maxDistance;
      else if(trade.orderType == OP_SELL)
         sl = trade.openPrice + maxDistance;
   }
   
   return NormalizeDouble(sl, Digits);
}

//+------------------------------------------------------------------+
//| Calculate automatic take profit                                  |
//+------------------------------------------------------------------+
double CalculateAutoTP(TradeInfo &trade, double sl)
{
   if(sl <= 0 || AutoTPRiskRewardRatio <= 0) return 0.0;
   
   double slDistance = MathAbs(trade.openPrice - sl);
   double tpDistance = slDistance * AutoTPRiskRewardRatio;
   
   double tp = 0.0;
   if(trade.orderType == OP_BUY)
      tp = trade.openPrice + tpDistance;
   else if(trade.orderType == OP_SELL)
      tp = trade.openPrice - tpDistance;
   
   return NormalizeDouble(tp, Digits);
}
//+------------------------------------------------------------------+
