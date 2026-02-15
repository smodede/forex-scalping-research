# Signal Harvester Risk Manager - Operations Handbook

**Version:** 3.0  
**Account Type:** FTMO $200K Configuration  
**Last Updated:** February 15, 2026

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Daily Operations](#daily-operations)
3. [Protecting Profits - Dynamic DD Management](#protecting-profits---dynamic-dd-management)
4. [Risk Minimization Strategy](#risk-minimization-strategy)
5. [Provider Lifecycle Management](#provider-lifecycle-management)
6. [FTMO-Specific Guidelines](#ftmo-specific-guidelines)
7. [Monitoring & Alerts](#monitoring--alerts)
8. [Troubleshooting](#troubleshooting)
9. [Performance Optimization](#performance-optimization)

---

## Quick Start

### Initial Configuration

**Current Settings (FTMO $200K):**
```mql4
Provider DD Thresholds:    12% / 18% / 22%
Absolute Loss Limit:       $2,500 per provider
Percentage Loss Limit:     1.5% per provider
Max Total Exposure:        8 providers × $2,500 = $20,000 (10% account)
```

**First-Time Setup:**
1. Configure provider IDs in settings: `"Provider1,12.0,18.0,22.0;Provider2,12.0,18.0,22.0"`
2. Enable absolute loss protection: `EnableAbsoluteLossProtection = true`
3. Verify audit log location: `shra_provider_audit_[AccountNumber].csv`
4. Test buttons and keyboard shortcuts (R = reset all, 1-9 = reset individual)

---

## Daily Operations

### Morning Checklist (Before Market Open)

**1. Review Overnight Activity**
```powershell
# View overnight events
Get-Content shra_provider_audit_410038624.csv | Select-String "2026.02.15"
```

**Check for:**
- ✅ Any kill switch activations
- ✅ WARNING or CRITICAL events
- ✅ Unusual provider behavior

**2. Verify GlobalVariables (Press F3 in MT4)**
```
SHRA_[Account]_[Provider]_PeakEquity    → Verify peak values
SHRA_[Account]_[Provider]_KillSwitch    → Confirm 0.0 (active) or 1.0 (killed)
```

**3. Check Chart Status**
- Green buttons = Active providers ✅
- Red buttons = Kill switch active 🚨
- Review any red providers, decide to reset or remove

### Intraday Monitoring (Every 4 Hours)

**Quick Status Check:**
1. Scan chart buttons for color changes
2. Check MT4 Experts tab for WARNING logs
3. Verify no FTMO daily loss breach (< $10,000)

**Actions if Provider Hits Warning (12% DD):**
- ⚠️ **Do Nothing** - Normal variance, system monitoring
- 📊 Review provider's open trades manually
- 📝 Note in trading journal for pattern tracking

**Actions if Provider Hits Critical (18% DD):**
- 🔴 EA automatically closed 20% worst trades
- 📊 Review remaining trades - consider manual closure
- 🤔 Evaluate if provider strategy changed

**Actions if Kill Switch Fires (22% DD or $2,500 loss):**
- 🚨 Provider stopped completely
- 📋 Document what happened in audit log
- 🔍 Review signal provider's SignalStart page
- ❌ Unsubscribe from signal provider immediately
- 🔄 Replace with new provider from vetted list

### Evening Wrap-Up

**1. Calculate Daily P&L**
```
Total Account P&L:     [Check MT4]
Per Provider P&L:      [Review audit log]
Progress to FTMO Target: [Track in spreadsheet]
```

**2. Update Provider Tracking Sheet**
| Provider | Today P&L | Week P&L | Current DD | Status | Action |
|----------|-----------|----------|------------|--------|--------|
| Provider1 | +$450 | +$1,200 | 3% | ✅ Good | Hold |
| Provider2 | -$120 | +$800 | 8% | ⚠️ Watch | Monitor |
| Provider3 | -$2,500 | -$2,500 | N/A | 🚨 Killed | Replace |

**3. Plan Tomorrow**
- Replace killed providers?
- Adjust any DD thresholds?
- Increase/decrease copy % at signal portal?

---

## Protecting Profits - Dynamic DD Management

### The Core Problem

**Your EA starts tracking from zero.** When a provider becomes profitable, you want to **protect those gains** by tightening drawdown thresholds.

### Strategy: The Profit Lock Protocol

#### **Phase 1: Testing Period (First 2 Weeks)**

**Goal:** Let provider establish track record without premature killing

**Settings:**
```mql4
Provider1,12.0,18.0,22.0    // Wide tolerance
```

**Rationale:**
- Allow for normal variance (good traders have 8-15% DD)
- $2,500 absolute loss still protects against total disasters
- Focus on identifying consistently profitable providers

---

#### **Phase 2: Profit Established (+$1,000 threshold met)**

**Trigger:** Provider reaches +$1,000 cumulative profit

**Action: Tighten Thresholds to Protect Gains**

**Before (Testing Phase):**
```mql4
Provider1,12.0,18.0,22.0
```

**After (Protecting $1,000 profit):**
```mql4
Provider1,8.0,12.0,15.0
```

**How to Update:**
1. Stop EA (remove from chart)
2. Edit input parameter: `Provider1,8.0,12.0,15.0`
3. Restart EA
4. Alternatively: Delete GlobalVariable `SHRA_[Account]_Provider1_PeakEquity` to reset tracking

**Effect:**
- Warning at 8% DD (was 12%) → Earlier alert
- Critical at 12% DD (was 18%) → Trims positions sooner
- Emergency at 15% DD (was 22%) → Tighter stop

**Example Scenario:**
```
Provider1 Peak:        +$1,500 (after fee reversal)
Allowed DD:           15% = $225 drawdown max
Kill switch trigger:  $1,500 - $225 = $1,275

Instead of allowing $1,500 → $0 (22% = $330 DD)
Now protecting at $1,275 floor
You secure $1,275 profit minimum (before kill switch)
```

---

#### **Phase 3: Major Profit Achieved (+$3,000 threshold met)**

**Trigger:** Provider reaches +$3,000 cumulative profit

**Action: Lock In Profits with Aggressive Protection**

**Settings:**
```mql4
Provider1,5.0,8.0,10.0    // Very tight profit protection
```

**Effect:**
- Warning at 5% DD → Almost immediate alert
- Critical at 8% DD → Quick damage control
- Emergency at 10% DD → Preserves 90% of peak

**Example:**
```
Provider1 Peak:        +$5,000
Allowed DD:           10% = $500
Kill switch at:       $4,500

You protect $4,500 minimum gain
Risk only $500 of the $5,000 profit
```

---

### Manual Profit Lock Process

**Step-by-Step:**

**1. Monitor Peak Equity**
```
Check GlobalVariable: SHRA_410038624_Provider1_PeakEquity
Current Value: 3200.00
```

**2. Decide Protection Level**
```
Peak $3,200 → Want to protect 90% = $2,880
Use 10% DD threshold: 3200 × 10% = $320 risk
```

**3. Update Configuration**
```mql4
Remove EA from chart
Edit input: Provider1,5.0,8.0,10.0
Reattach EA to chart
```

**4. Verify New Settings**
```
Check audit log for: "Initialized with N providers"
Verify button still shows Provider1
```

**5. Monitor First Day**
- Ensure warnings aren't too frequent
- If 5% DD hits too often → loosen to 6%/9%/12%

---

### Profit Lock Table (Quick Reference)

| Provider Profit | Risk Tolerance | Warn DD | Crit DD | Emerg DD | Max Risk |
|----------------|----------------|---------|---------|----------|----------|
| $0 - $500 | Testing | 12% | 18% | 22% | Unlimited* |
| $500 - $1,500 | Moderate | 10% | 15% | 18% | $270 |
| $1,500 - $3,000 | Conservative | 8% | 12% | 15% | $450 |
| $3,000+ | Profit Lock | 5% | 8% | 10% | $300-$500 |

*Limited by $2,500 absolute loss

---

### Advanced: Trailing Profit Stop

**Concept:** Automatically raise protection floor as provider profits increase

**Manual Implementation:**

**Every $1,000 profit milestone:**
1. Reset peak equity (delete GlobalVariable)
2. Tighten thresholds by 2%
3. Document in spreadsheet

**Example Timeline:**
```
Week 1: Provider1 → +$500  → Settings: 12/18/22 (testing)
Week 2: Provider1 → +$1,200 → Settings: 10/15/18 (moderate)
Week 4: Provider1 → +$2,800 → Settings: 8/12/15 (conservative)
Week 6: Provider1 → +$4,500 → Settings: 5/8/10 (profit lock)
```

---

## Risk Minimization Strategy

### Pre-Provider Selection (Layer 1)

**SignalStart Filters (Critical!):**

```
✅ Max Historical DD:      12-15% (no higher for FTMO)
✅ Min Profit Factor:      1.6+
✅ Min Win Rate:           55%+
✅ Min Trades:            150+
✅ Max Age:               6 months (recent = relevant)
✅ Active last 7 days:    Yes
✅ Subscriber count:      50+ (social proof)
✅ Reviews:              Read last 10, check for complaints
```

**Red Flags (Never Subscribe):**
- ❌ DD spike recent (went from 8% → 15% in last month)
- ❌ Strategy change mentioned
- ❌ Gaps in trading history
- ❌ Complaints about "sudden losses"
- ❌ Very high DD (>20%) even if profitable

---

### Position Sizing at Signal Portal (Layer 2)

**Copy % Configuration:**

**Conservative Start (First 2 Weeks):**
```
Copy %:               20-25%
Max Lot Size:        0.3 per position
Max Open Trades:     3 per provider
Risk per Trade:      0.3-0.5% of signal's account
```

**Moderate (After $1K Profit):**
```
Copy %:               30-40%
Max Lot Size:        0.5 per position
Max Open Trades:     5 per provider
```

**Aggressive (Proven Winner):**
```
Copy %:               40-50%
Max Lot Size:        1.0 per position
Max Open Trades:     8 per provider
```

**Example Math:**
```
Signal trades:        1.0 lot on their $10K account (10% risk)
Your copy % :         30%
Your position:        0.3 lots on $200K account (0.045% risk)
```

---

### Diversification Rules (Layer 3)

**Portfolio Allocation:**

```
Core Providers (3):      40% exposure × $20K = $8,000
    - Low DD (8-10% historical)
    - 40-50% copy rate
    - $2,666 max loss each

Growth Providers (3):    35% exposure × $20K = $7,000
    - Medium DD (12-15% historical)
    - 30-40% copy rate
    - $2,333 max loss each

Test Providers (2):      25% exposure × $20K = $5,000
    - Higher DD (15-18% historical)
    - 20-25% copy rate
    - $2,500 max loss each
```

**Strategy Diversification:**
- ✅ 2-3 Trend following
- ✅ 2-3 Mean reversion
- ✅ 2-3 Scalping
- ❌ Never all same strategy type

---

### Correlation Management (Layer 4)

**Problem:** All providers lose simultaneously during market events

**Solution: Time Zone & Pair Diversification**

```
Group A:  3 providers → Focus EUR/USD, GBP/USD (London session)
Group B:  2 providers → Focus USD/JPY, AUD/USD (Asian session)
Group C:  3 providers → Focus Gold, Indices (Any session)
```

**Check Weekly:**
- If 5+ providers all negative same day → Too correlated!
- Reduce exposure or diversify better

---

### Maximum Risk Calculation

**Per Provider:**
```
Absolute Loss:    $2,500 (1.25% of $200K)
OR
Percentage Loss:  $3,000 (1.5% of $200K)

Effective limit:  $2,500 (whichever hits first)
```

**Portfolio:**
```
8 providers × $2,500 = $20,000
$20,000 / $200,000 = 10%

Matches FTMO max DD limit exactly! ✅
```

**Worst Case Scenario:**
```
All 8 providers killed simultaneously:  -$20,000
FTMO account still passes:              -10% (under 10% limit)
Verification phase still possible:      Yes
```

---

### Emergency Procedures

**If Total Account DD Reaches 7% ($14,000):**

**Immediate Actions:**
1. 🚨 **Reduce all copy % by 50%** at signal portal
2. 📊 Review audit log for which providers caused losses
3. ❌ Manually close worst provider's trades (don't wait for EA)
4. 🔍 Check for market event (news, correlation spike)
5. ⏸️ Consider pausing all copying for 24 hours

**If Daily Loss Reaches $8,000 (approaching $10K FTMO limit):**

**CRISIS MODE:**
1. 🛑 **Close ALL open trades immediately**
2. ⏸️ **Unsubscribe from ALL signals** at portal
3. 📞 Document incident for FTMO support
4. 🔄 Reset strategy - start over with 2-3 vetted providers only
5. ⚖️ Reduce copy % to 15-20% for 1 week recovery

---

## Provider Lifecycle Management

### Stage 1: Onboarding (Days 1-14)

**Objective:** Validate signal quality without major risk

**Settings:**
```mql4
Copy %:           20-25%
DD Thresholds:    12/18/22 (wide tolerance)
Watch Time:       Daily review
```

**Success Criteria:**
- ✅ No kill switch activation
- ✅ Positive or neutral P&L
- ✅ No DD >12% warning

**Fail → Kill:**
- ❌ Hits $2,500 absolute loss
- ❌ Multiple 18% critical DD events
- ❌ Chaotic trading pattern

---

### Stage 2: Growth (Weeks 2-8)

**Objective:** Increase exposure on proven winners

**Settings:**
```mql4
Copy %:           30-40% (increase by 10% per week)
DD Thresholds:    10/15/18 (moderate protection)
Review:           Weekly performance check
```

**Milestones:**
- Week 4: +$1,000 cumulative → increase to 35%
- Week 6: +$2,000 cumulative → increase to 40%
- Week 8: +$3,000 cumulative → consider 45-50%

**Warning Signs:**
- ⚠️ DD increasing trend (5% → 8% → 11%)
- ⚠️ Win rate declining
- ⚠️ Trade frequency changed dramatically

---

### Stage 3: Maturity (Month 2+)

**Objective:** Protect hard-earned profits

**Settings:**
```mql4
Copy %:           40-50% (max exposure)
DD Thresholds:    8/12/15 (tight profit protection)
OR (if >$3K profit): 5/8/10 (profit lock mode)
Review:           Monthly performance review
```

**Maintenance:**
- Compare month-over-month performance
- Check if still meeting SignalStart quality filters
- Read recent subscriber reviews
- Verify no strategy changes announced

**Graduation to "Core Provider":**
- 6+ months profitable
- Max DD never exceeded 12%
- Consistent positive weeks (80%+ green)
- Move to 50% copy, become portfolio cornerstone

---

### Stage 4: Decline or Exit

**Triggers:**
- 🚨 Kill switch fired (22% DD or $2,500 loss)
- ⚠️ 3+ consecutive critical DD events (18%)
- 📉 Negative 2 consecutive months
- 🔄 Provider announced strategy change
- 💬 Multiple subscriber complaints

**Exit Protocol:**
1. **Gradual Reduction Method (Preferred):**
   - Week 1: Reduce copy % to 20%
   - Week 2: Reduce to 10%
   - Week 3: Unsubscribe if still negative
   - Monitor if improvement occurs

2. **Immediate Exit (Emergency):**
   - Kill switch fired → unsubscribe same day
   - Check if provider issues refund
   - Document reason in audit log

3. **Replace Immediately:**
   - Have 2-3 backup providers pre-vetted
   - Start new provider at 20% Stage 1
   - Maintain 8 provider target

---

## FTMO-Specific Guidelines

### Challenge Phase (30 Days to +$20K)

**Week 1-2: Conservative Start**
```
Providers:        5 (not 8 initially)
Copy %:          25-30%
Goal:            +$3,000 - $5,000
Focus:           No kill switches, build confidence
```

**Week 3: Ramp Up**
```
Providers:        Add 2-3 more (7-8 total)
Copy %:          30-40% on proven ones
Goal:            +$6,000 - $10,000 cumulative
Focus:           Increase winners, cut losers fast
```

**Week 4: Target Push**
```
Providers:        6-8 survivors
Copy %:          40-50% on top performers
Goal:            Reach +$20,000 target
Focus:           Risk management to preserve gains
```

---

### Verification Phase (60 Days to +$10K)

**Strategy: Defensive Rally**

```
Use proven providers from Challenge
Copy %:           25-35% (lower than Challenge)
Providers:        5-6 (reduce from 8)
Goal:            $170/day average (~$10K/60 days)
```

**Key Difference:**
- Challenge: Growth mindset, tolerate variance
- Verification: **Preservation mindset**, minimize risk

---

### FTMO Breach Prevention

**Daily Loss Monitoring:**

Create Excel tracker:
```
Date | Start Equity | Current | Daily P&L | % of $10K Limit | Alert
2/15 | $202,000    | $203,500| +$1,500  | 15% used       | ✅
2/16 | $203,500    | $201,800| -$1,700  | 17% used       | ⚠️
2/17 | $201,800    | $197,500| -$4,300  | 43% used       | 🚨
```

**If Daily Loss >$7,000:**
- 🚨 Manually close all trades
- ⏸️ Pause copying until next day
- 🔍 Analyze what happened

---

## Monitoring & Alerts

### Daily Alert System

**Use MT4's Alert System + Phone Notifications:**

**Critical Alerts (Immediate Action):**
- 🚨 Kill switch activation (any provider)
- 🚨 Daily loss >$5,000
- 🚨 Total account DD >7%

**Warning Alerts (Review Within 1 Hour):**
- ⚠️ Provider hits 12% warning DD
- ⚠️ 3+ providers negative simultaneously
- ⚠️ Daily loss >$3,000

**Info Alerts (Review End of Day):**
- ℹ️ Provider closed trades (audit log entry)
- ℹ️ Daily profit >$2,000 (celebrate!)

---

### Weekly Performance Report

**Create Spreadsheet Tracker:**

| Provider | Week P&L | Peak | Current | DD% | Trades | Win% | Status | Action |
|----------|----------|------|---------|-----|--------|------|--------|--------|
| Prov1 | +$1,200 | $5,200 | $5,200 | 0% | 18 | 67% | ✅ | Hold 50% |
| Prov2 | +$450 | $2,800 | $2,500 | 11% | 25 | 52% | ⚠️ | Monitor |
| Prov3 | -$2,500 | $0 | -$2,500 | N/A | 15 | 33% | 🚨 | Killed |

**Metrics to Track:**
- Total portfolio P&L
- Average DD per provider
- Win rate by provider
- Kill switch count
- FTMO target progress

---

## Troubleshooting

### Issue: Provider killed but performing well on SignalStart

**Cause:** Your entry timing different from their history

**Solution:**
1. Check your peak equity vs their stats
2. Verify copy % not too aggressive
3. Consider resetting peak (delete GlobalVariable)
4. Restart with wider DD thresholds (12/18/22)

---

### Issue: Too many warnings, buttons constantly red

**Cause:** DD thresholds too tight for provider's style

**Solution:**
1. Review historical DD on SignalStart
2. Loosen thresholds to 1.2× their historical DD
3. Example: 12% historical → use 14/18/22 settings

---

### Issue: Absolute loss killing providers too early

**Cause:** $2,500 limit too tight for testing period

**Solution:**
1. Temporary: Increase to $3,000 for first month
2. Reduce copy % to 20% instead
3. After validation, return to $2,500

---

### Issue: Not tracking providers correctly

**Cause:** Comment tags not matching

**Solution:**
1. Check actual trade comments in MT4
2. Verify ProviderDD settings match exactly
3. Example: If comment is "SS_TrendMaster", use `SS_TrendMaster,12.0,18.0,22.0`

---

### Issue: GlobalVariables lost/corrupted

**Symptom:** Peak equity resets to 0 after restart

**Solution:**
1. Check `F3` → Global Variables list
2. Manually set: `SHRA_[Account]_[Provider]_PeakEquity = [value]`
3. For fresh start: Delete all SHRA_ variables
4. Restart EA to rebuild

---

## Performance Optimization

### Monthly Review Checklist

**Portfolio Health:**
- [ ] Kill switch count <3 per month
- [ ] Average provider profit positive
- [ ] No provider with DD >15% sustained
- [ ] At least 5 active providers

**FTMO Progress:**
- [ ] On track for target ($20K Challenge, $10K Verification)
- [ ] Daily loss never exceeded $5,000
- [ ] Max DD stayed under 8%

**Strategy Effectiveness:**
- [ ] Profit lock protocol working? (Check if tight DD preserves gains)
- [ ] Absolute loss catching bad providers early?
- [ ] Correlation low? (Not all providers negative same day)

---

### Optimization Cycle (Every Month)

**1. Analyze Kill Switches:**
```
If 0-1: DD thresholds optimal ✅
If 2-3: Acceptable, normal filtering ⚖️
If 4+: Too tight OR bad provider selection ❌
```

**Action:**
- If too many kills: Loosen emergency DD by 2-3%
- If bad providers: Improve SignalStart filtering

**2. Profit Lock Effectiveness:**
```
Check: Did tight DD preserve profits?
Example: Provider peaked $5K, DD to $4K, recovered $5.5K
Result: ✅ Tight DD (10%) prevented deeper loss
```

**3. Portfolio Rebalancing:**
- Remove consistent losers
- Increase copy % on consistent winners
- Add 1-2 new tested providers quarterly

---

## Advanced Techniques

### Dynamic Threshold Adjustment Formula

**Automatic Scaling Based on Profit:**

```
If Provider Peak < $1,000:
    Use: 12 / 18 / 22 (testing)

If Provider Peak $1,000 - $3,000:
    Use: 10 / 15 / 18 (moderate)

If Provider Peak $3,000+:
    Emerg DD% = 10 + (5 × $1000 / Peak)
    Example: $5,000 peak → 10 + (5 × 0.2) = 11% emergency DD
```

**Implementation:**
- Update manually monthly
- Or reset peak equity periodically to retighten

---

### Stress Testing Your Settings

**Simulate Worst-Case Scenarios:**

**Scenario 1: Flash Crash**
```
All 8 providers -15% simultaneously
Total loss: 8 × ($3,000 equity × 15%) = $3,600
Account impact: 1.8%
FTMO Breach: No ✅
```

**Scenario 2: 4 Providers Killed**
```
4 × $2,500 = $10,000 loss
Account impact: 5%
FTMO Breach: No ✅
Can we continue? Yes, 4 survivors remain
```

**Scenario 3: News Event**
```
3 providers stopped out: -$7,500
1 provider big win: +$3,000
Net: -$4,500 (2.25%)
FTMO Breach: No ✅
```

---

## Conclusion

**Key Principles:**

1. **Start Conservative** → Test providers with wide thresholds
2. **Tighten Gradually** → Protect profits as they accumulate
3. **Never Override Safety** → $2,500 absolute loss is non-negotiable
4. **Document Everything** → Audit log + spreadsheet tracking
5. **React Fast** → Kill switches fire for a reason, respect them

**Success Metrics:**

- ✅ 70%+ provider survival rate (5-6 of 8 active)
- ✅ <3 kill switches per month
- ✅ Positive portfolio P&L every month
- ✅ FTMO target achieved within timeframe

---

## Quick Reference Card

### Keyboard Shortcuts
- `R` → Reset ALL kill switches
- `1-9` → Reset provider #1-9
- `F3` → View GlobalVariables

### Emergency Contacts
- FTMO Support: [support link]
- SignalStart Support: [support link]
- Broker Support: [support link]

### Files to Monitor
- `shra_provider_audit_[Account].csv` → Daily review
- GlobalVariables (F3) → Peak equity verification
- MT4 Experts tab → Real-time alerts

---

**Remember: This EA is a SAFETY NET, not a profit generator. Your success depends on selecting good signal providers. The EA ensures bad ones don't devastate your account.**

**Trade Smart. Protect Always. Profit Consistently.** 🎯
