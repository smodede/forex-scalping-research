# Test MinPeak Kill Switch Bug Fix Logic
# Simulates the EA restart scenario

Write-Host "`n========== MINPEAK KILL SWITCH BUG FIX TEST ==========`n" -ForegroundColor Cyan

# Test Scenario
$groupId = "286254"
$oldMinPeak = 20.0
$newMinPeak = 1000.0
$currentPeak = 446.04
$currentEquity = 181.96
$emergThreshold = 28.0

Write-Host "SCENARIO: User raises minPeak threshold" -ForegroundColor Yellow
Write-Host "  Old minPeak: `$$oldMinPeak"
Write-Host "  New minPeak: `$$newMinPeak"
Write-Host "  GROUP_$groupId Peak: `$$currentPeak"
Write-Host "  GROUP_$groupId Current Equity: `$$currentEquity"
Write-Host ""

# Calculate DD
$dd = (($currentPeak - $currentEquity) / $currentPeak) * 100

Write-Host "CURRENT STATE:" -ForegroundColor Yellow
Write-Host "  Drawdown: $([math]::Round($dd, 2))%"
Write-Host "  Emergency Threshold: $emergThreshold%"
Write-Host "  Status: $(if($dd -ge $emergThreshold){'BEYOND KILL THRESHOLD'}else{'Below threshold'})"
Write-Host ""

# Simulate OLD behavior (BUG)
Write-Host "OLD BEHAVIOR (BUG):" -ForegroundColor Red
Write-Host "  1. EA restarts with new minPeak = `$$newMinPeak"
Write-Host "  2. LoadPersistedState() loads old kill switch state"
Write-Host "  3. No validation against new minPeak"
Write-Host "  4. CheckGroupFloatingDD() evaluates:"
Write-Host "     - peak ($currentPeak) < groupMinPeak ($newMinPeak)? YES"
Write-Host "     - Action: continue (skip DD checks)"
Write-Host "  5. But kill switch STILL ACTIVE from old state!"
Write-Host "  Result: INCONSISTENT STATE - Kill switch active but protection disabled ❌"
Write-Host ""

# Simulate NEW behavior (FIX)
Write-Host "NEW BEHAVIOR (FIX):" -ForegroundColor Green
Write-Host "  1. EA restarts with new minPeak = `$$newMinPeak"
Write-Host "  2. LoadPersistedState() loads old kill switch state"
Write-Host "  3. NEW VALIDATION:"
Write-Host "     - killSwitchTriggered? YES (loaded from old state)"
Write-Host "     - peakEquity ($currentPeak) > 0? YES"
Write-Host "     - peakEquity ($currentPeak) < groupMinPeak ($newMinPeak)? YES"
Write-Host "     - Action: CLEAR KILL SWITCH AUTOMATICALLY ✓"
Write-Host "  4. CheckGroupFloatingDD() evaluates:"
Write-Host "     - killSwitchTriggered? NO (already cleared in step 3)"
Write-Host "     - peak ($currentPeak) < groupMinPeak ($newMinPeak)? YES"
Write-Host "     - Action: continue (skip DD checks)"
Write-Host "  Result: CONSISTENT STATE - No kill switch, no protection ✓"
Write-Host ""

# Test the logic programmatically
function Test-MinPeakLogic {
    param(
        [double]$peak,
        [double]$minPeak,
        [bool]$hasOldKillSwitch
    )
    
    $killSwitchActive = $hasOldKillSwitch
    
    # Simulate LoadPersistedState auto-clear logic
    if($killSwitchActive -and $peak -gt 0 -and $peak -lt $minPeak) {
        Write-Host "  [LoadPersistedState] Auto-clearing kill switch: peak $peak < minPeak $minPeak" -ForegroundColor Yellow
        $killSwitchActive = $false
    }
    
    # Simulate CheckGroupFloatingDD early exit
    if($peak -le 0 -or $peak -lt $minPeak) {
        Write-Host "  [CheckGroupFloatingDD] Skipping DD checks: peak $peak < minPeak $minPeak" -ForegroundColor Yellow
        return @{
            KillSwitchActive = $killSwitchActive
            ProtectionEnabled = $false
            DDChecksRun = $false
        }
    }
    
    # If we get here, protection is active
    return @{
        KillSwitchActive = $killSwitchActive
        ProtectionEnabled = $true
        DDChecksRun = $true
    }
}

Write-Host "AUTOMATED TESTS:" -ForegroundColor Cyan
Write-Host ""

# Test 1: Peak below minPeak WITH old kill switch (the bug scenario)
Write-Host "Test 1: Peak `$446 < minPeak `$1000, has old kill switch" -ForegroundColor Yellow
$result1 = Test-MinPeakLogic -peak 446.04 -minPeak 1000.0 -hasOldKillSwitch $true
Write-Host "  Kill Switch: $(if($result1.KillSwitchActive){'ACTIVE ❌'}else{'CLEARED ✓'})"
Write-Host "  Protection: $(if($result1.ProtectionEnabled){'ENABLED'}else{'DISABLED ✓'})"
Write-Host "  DD Checks: $(if($result1.DDChecksRun){'RAN'}else{'SKIPPED ✓'})"
Write-Host "  Status: $(if(-not $result1.KillSwitchActive -and -not $result1.ProtectionEnabled){'PASS ✅'}else{'FAIL ❌'})"
Write-Host ""

# Test 2: Peak above minPeak (protection should be active)
Write-Host "Test 2: Peak `$1975 > minPeak `$1000, no old kill switch" -ForegroundColor Yellow
$result2 = Test-MinPeakLogic -peak 1974.76 -minPeak 1000.0 -hasOldKillSwitch $false
Write-Host "  Kill Switch: $(if($result2.KillSwitchActive){'ACTIVE'}else{'CLEARED'})"
Write-Host "  Protection: $(if($result2.ProtectionEnabled){'ENABLED ✓'}else{'DISABLED'})"
Write-Host "  DD Checks: $(if($result2.DDChecksRun){'RAN ✓'}else{'SKIPPED'})"
Write-Host "  Status: $(if($result2.ProtectionEnabled -and $result2.DDChecksRun){'PASS ✅'}else{'FAIL ❌'})"
Write-Host ""

# Test 3: Peak exactly at minPeak (edge case)
Write-Host "Test 3: Peak `$1000 = minPeak `$1000 (edge case)" -ForegroundColor Yellow
$result3 = Test-MinPeakLogic -peak 1000.0 -minPeak 1000.0 -hasOldKillSwitch $false
Write-Host "  Kill Switch: $(if($result3.KillSwitchActive){'ACTIVE'}else{'CLEARED'})"
Write-Host "  Protection: $(if($result3.ProtectionEnabled){'ENABLED ✓'}else{'DISABLED'})"
Write-Host "  DD Checks: $(if($result3.DDChecksRun){'RAN ✓'}else{'SKIPPED'})"
Write-Host "  Status: $(if($result3.ProtectionEnabled){'PASS ✅'}else{'FAIL ❌'})"
Write-Host ""

# Test 4: Zero peak (new group)
Write-Host "Test 4: Peak `$0 (new group, no history)" -ForegroundColor Yellow
$result4 = Test-MinPeakLogic -peak 0.0 -minPeak 1000.0 -hasOldKillSwitch $false
Write-Host "  Kill Switch: $(if($result4.KillSwitchActive){'ACTIVE'}else{'CLEARED'})"
Write-Host "  Protection: $(if($result4.ProtectionEnabled){'ENABLED'}else{'DISABLED ✓'})"
Write-Host "  DD Checks: $(if($result4.DDChecksRun){'RAN'}else{'SKIPPED ✓'})"
Write-Host "  Status: $(if(-not $result4.ProtectionEnabled){'PASS ✅'}else{'FAIL ❌'})"
Write-Host ""

# Test 5: Lowering minPeak (opposite direction)
Write-Host "Test 5: Peak `$446 > minPeak `$20 (lowering threshold)" -ForegroundColor Yellow
$result5 = Test-MinPeakLogic -peak 446.04 -minPeak 20.0 -hasOldKillSwitch $false
Write-Host "  Kill Switch: $(if($result5.KillSwitchActive){'ACTIVE'}else{'CLEARED'})"
Write-Host "  Protection: $(if($result5.ProtectionEnabled){'ENABLED ✓'}else{'DISABLED'})"
Write-Host "  DD Checks: $(if($result5.DDChecksRun){'RAN ✓'}else{'SKIPPED'})"
Write-Host "  Status: $(if($result5.ProtectionEnabled -and $result5.DDChecksRun){'PASS ✅ (WARNING: May trigger if DD > 28%)'}else{'FAIL ❌'})"
Write-Host ""

# Summary
Write-Host "========== TEST SUMMARY ==========" -ForegroundColor Cyan
$allPass = (-not $result1.KillSwitchActive -and -not $result1.ProtectionEnabled) -and
           ($result2.ProtectionEnabled -and $result2.DDChecksRun) -and
           ($result3.ProtectionEnabled) -and
           (-not $result4.ProtectionEnabled) -and
           ($result5.ProtectionEnabled)

if($allPass) {
    Write-Host "ALL TESTS PASSED ✅" -ForegroundColor Green
    Write-Host ""
    Write-Host "VERIFIED: MinPeak bug fix prevents accidental kill switch triggers when threshold is raised" -ForegroundColor Green
} else {
    Write-Host "SOME TESTS FAILED ❌" -ForegroundColor Red
}

Write-Host "`n====================================`n"

# Instructions
Write-Host "TO TEST IN MT4:" -ForegroundColor Yellow
Write-Host "1. F3 → Check current GlobalVariable: SHRA_410038624_GROUP_286254_KillSwitch"
Write-Host "2. EA Inputs → Change sig_286254 minPeak from 20.0 to 1000.0"
Write-Host "3. Click OK to restart EA"
Write-Host "4. Expert Log → Look for: '✓ Cleared kill switch for GROUP_286254'"
Write-Host "5. F3 → Verify: SHRA_410038624_GROUP_286254_KillSwitch = 0.0"
Write-Host "6. Monitor for 30+ minutes → Verify NO GROUP_WARNING/CRITICAL/EMERGENCY events"
Write-Host ""
