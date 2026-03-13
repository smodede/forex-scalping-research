# Protection Systems Analysis
$logPath = "C:\Users\m_ode\AppData\Roaming\MetaQuotes\Terminal\56EE5B2C68594C11EBC44B2E705CB8B7\MQL4\Files\shra_provider_audit_410038624.csv"

Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   PROTECTION SYSTEMS HEALTH CHECK                                ║" -ForegroundColor Cyan
Write-Host "║   Account: 410038624 (FTMO $200K)                               ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Import data
Write-Host "[1/6] Loading audit log..." -ForegroundColor Yellow
$data = Import-Csv $logPath -Header 'Timestamp','Account','Provider','EventType','Peak','Current','DDPercent','TradesCount','Details'

$data | ForEach-Object { 
    try {
        $_.Timestamp = [DateTime]::ParseExact($_.Timestamp, 'yyyy.MM.dd HH:mm:ss', $null)
    } catch {
        # Skip header row
    }
    $_.Peak = try { [double]$_.Peak } catch { 0.0 }
    $_.Current = try { [double]$_.Current } catch { 0.0 }
    $_.DDPercent = try { [double]$_.DDPercent } catch { 0.0 }
    $_.TradesCount = try { [int]$_.TradesCount } catch { 0 }
}

# Filter out invalid entries
$data = $data | Where-Object { $_.Timestamp -is [DateTime] }

Write-Host "  ✓ Loaded $($data.Count) valid entries`n" -ForegroundColor Green

# ============================================================================
# 1. KILL SWITCH ANALYSIS
# ============================================================================
Write-Host "[2/6] Analyzing Kill Switch Protection..." -ForegroundColor Yellow

$killSwitches = $data | Where-Object { $_.EventType -match 'KILL_SWITCH' }
$providerKills = $killSwitches | Where-Object { $_.Provider -notmatch 'GROUP_|ACCOUNT_WIDE' }
$groupKills = $killSwitches | Where-Object { $_.Provider -match 'GROUP_' }
$accountKills = $killSwitches | Where-Object { $_.Provider -eq 'ACCOUNT_WIDE' }

Write-Host "`n  🛡️  KILL SWITCH SUMMARY:" -ForegroundColor Cyan
Write-Host "    Total Kill Switches:     $($killSwitches.Count)" -ForegroundColor $(if($killSwitches.Count -eq 0){'Green'}else{'Yellow'})
Write-Host "    ├─ Provider Level:       $($providerKills.Count)" -ForegroundColor $(if($providerKills.Count -eq 0){'Green'}else{'Yellow'})
Write-Host "    ├─ Group Level:          $($groupKills.Count)" -ForegroundColor $(if($groupKills.Count -eq 0){'Green'}else{'Yellow'})
Write-Host "    └─ Account Level:        $($accountKills.Count)" -ForegroundColor $(if($accountKills.Count -eq 0){'Green'}else{'Red'})

if($killSwitches.Count -gt 0) {
    Write-Host "`n  📋 RECENT KILL SWITCHES (Last 20):" -ForegroundColor Yellow
    $killSwitches | Sort-Object Timestamp -Descending | Select-Object -First 20 | ForEach-Object {
        Write-Host "    [$($_.Timestamp.ToString('yyyy-MM-dd HH:mm'))] $($_.Provider)" -ForegroundColor Red
        Write-Host "      Details: $($_.Details)" -ForegroundColor Gray
    }
} else {
    Write-Host "    ✅ No kill switches triggered - protection thresholds not breached" -ForegroundColor Green
}

# ============================================================================
# 2. WARNING & EMERGENCY LEVELS
# ============================================================================
Write-Host "`n[3/6] Analyzing Warning & Emergency Levels..." -ForegroundColor Yellow

$warnings = $data | Where-Object { $_.EventType -match 'WARNING' }
$emergencies = $data | Where-Object { $_.EventType -match 'EMERGENCY' }
$criticals = $data | Where-Object { $_.EventType -match 'CRITICAL' }

Write-Host "`n  ⚠️  ALERT LEVELS:" -ForegroundColor Cyan
Write-Host "    Warnings (12% DD):       $($warnings.Count)" -ForegroundColor Yellow
Write-Host "    Emergencies (18% DD):    $($emergencies.Count)" -ForegroundColor $(if($emergencies.Count -gt 0){'Red'}else{'Yellow'})
Write-Host "    Critical Events:         $($criticals.Count)" -ForegroundColor $(if($criticals.Count -gt 0){'Red'}else{'Yellow'})

if($warnings.Count -eq 0 -and $emergencies.Count -eq 0) {
    Write-Host "    ✅ No warnings or emergencies - all providers within safe DD thresholds" -ForegroundColor Green
} else {
    if($warnings.Count -gt 0) {
        Write-Host "`n  📊 RECENT WARNINGS (Last 10):" -ForegroundColor Yellow
        $warnings | Sort-Object Timestamp -Descending | Select-Object -First 10 | ForEach-Object {
            Write-Host "    [$($_.Timestamp.ToString('yyyy-MM-dd HH:mm'))] $($_.Provider) - DD: $($_.DDPercent)%" -ForegroundColor Yellow
        }
    }
    if($emergencies.Count -gt 0) {
        Write-Host "`n  🚨 RECENT EMERGENCIES (Last 10):" -ForegroundColor Red
        $emergencies | Sort-Object Timestamp -Descending | Select-Object -First 10 | ForEach-Object {
            Write-Host "    [$($_.Timestamp.ToString('yyyy-MM-dd HH:mm'))] $($_.Provider) - DD: $($_.DDPercent)%" -ForegroundColor Red
        }
    }
}

# ============================================================================
# 3. TRADE TRIM ANALYSIS
# ============================================================================
Write-Host "`n[4/6] Analyzing Trade Trim Protection..." -ForegroundColor Yellow

$trims = $data | Where-Object { $_.EventType -match 'TRIM' }
$accountTrims = $trims | Where-Object { $_.Provider -eq 'ACCOUNT_WIDE' }
$groupTrims = $trims | Where-Object { $_.Provider -match 'GROUP_' }

Write-Host "`n  ✂️  TRADE TRIM SUMMARY:" -ForegroundColor Cyan
Write-Host "    Total Trim Events:       $($trims.Count)" -ForegroundColor $(if($trims.Count -eq 0){'Green'}else{'Yellow'})
Write-Host "    ├─ Account Level:        $($accountTrims.Count)" -ForegroundColor $(if($accountTrims.Count -eq 0){'Green'}else{'Yellow'})
Write-Host "    └─ Group Level:          $($groupTrims.Count)" -ForegroundColor $(if($groupTrims.Count -eq 0){'Green'}else{'Yellow'})

if($trims.Count -gt 0) {
    Write-Host "`n  📋 RECENT TRIMS (Last 10):" -ForegroundColor Yellow
    $trims | Sort-Object Timestamp -Descending | Select-Object -First 10 | ForEach-Object {
        Write-Host "    [$($_.Timestamp.ToString('yyyy-MM-dd HH:mm'))] $($_.Provider)" -ForegroundColor Yellow
        Write-Host "      $($_.Details)" -ForegroundColor Gray
    }
} else {
    Write-Host "    ✅ No trade trims needed - DD levels stayed within emergency thresholds" -ForegroundColor Green
}

# ============================================================================
# 4. FTMO DAILY LOSS PROTECTION
# ============================================================================
Write-Host "`n[5/6] Analyzing FTMO Daily Loss Protection..." -ForegroundColor Yellow

$today = (Get-Date).Date
$todayAccountStatus = $data | Where-Object { 
    $_.Provider -eq 'ACCOUNT_WIDE' -and 
    $_.EventType -eq 'ACCOUNT_STATUS' -and 
    $_.Timestamp.Date -eq $today 
} | Sort-Object Timestamp -Descending | Select-Object -First 1

if($todayAccountStatus) {
    # Parse account status details
    if($todayAccountStatus.Details -match 'Daily Total:\s*\$?\s*(-?\d+\.?\d*)') {
        $dailyTotal = [double]$matches[1]
        $ftmoLimit = -10000
        $distanceToLimit = $ftmoLimit - $dailyTotal
        $safetyPercent = ($distanceToLimit / 10000) * 100
        
        Write-Host "`n  🏦 FTMO DAILY LOSS PROTECTION:" -ForegroundColor Cyan
        Write-Host "    Daily Limit:             -$10,000.00" -ForegroundColor Gray
        Write-Host "    Current Daily P&L:       `$$($dailyTotal.ToString('N2'))" -ForegroundColor $(if($dailyTotal -gt 0){'Green'}elseif($dailyTotal -gt -5000){'Yellow'}else{'Red'})
        Write-Host "    Distance to Limit:       `$$($distanceToLimit.ToString('N2'))" -ForegroundColor $(if($distanceToLimit -gt 5000){'Green'}elseif($distanceToLimit -gt 2000){'Yellow'}else{'Red'})
        Write-Host "    Safety Margin:           $($safetyPercent.ToString('N1'))%" -ForegroundColor $(if($safetyPercent -gt 50){'Green'}elseif($safetyPercent -gt 20){'Yellow'}else{'Red'})
        
        if($safetyPercent -gt 70) {
            Write-Host "    ✅ EXCELLENT - Well within safe limits" -ForegroundColor Green
        } elseif($safetyPercent -gt 40) {
            Write-Host "    ✅ GOOD - Safe trading zone" -ForegroundColor Green
        } elseif($safetyPercent -gt 20) {
            Write-Host "    ⚠️  CAUTION - Approaching warning zone" -ForegroundColor Yellow
        } else {
            Write-Host "    🚨 DANGER - Close to FTMO limit!" -ForegroundColor Red
        }
    }
}

# ============================================================================
# 5. RESET & RECOVERY EVENTS
# ============================================================================
Write-Host "`n[6/6] Analyzing Reset & Recovery Events..." -ForegroundColor Yellow

$resets = $data | Where-Object { $_.EventType -match 'RESET' }
$autoResets = $resets | Where-Object { $_.EventType -eq 'AUTO_RESET' }
$manualResets = $resets | Where-Object { $_.EventType -ne 'AUTO_RESET' }

Write-Host "`n  🔄 RESET EVENTS:" -ForegroundColor Cyan
Write-Host "    Total Resets:            $($resets.Count)" -ForegroundColor Gray
Write-Host "    ├─ Auto Resets:          $($autoResets.Count)" -ForegroundColor Yellow
Write-Host "    └─ Manual Resets:        $($manualResets.Count)" -ForegroundColor Cyan

if($autoResets.Count -gt 0) {
    Write-Host "`n  🤖 RECENT AUTO RESETS (Last 10):" -ForegroundColor Yellow
    $autoResets | Sort-Object Timestamp -Descending | Select-Object -First 10 | ForEach-Object {
        Write-Host "    [$($_.Timestamp.ToString('yyyy-MM-dd HH:mm'))] $($_.Provider)" -ForegroundColor Yellow
        Write-Host "      $($_.Details)" -ForegroundColor Gray
    }
}

# ============================================================================
# OVERALL PROTECTION HEALTH SCORE
# ============================================================================
Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   PROTECTION SYSTEM HEALTH SCORE                                 ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$healthScore = 100
$healthIssues = @()

# Deduct points for protection triggers
if($accountKills.Count -gt 0) {
    $healthScore -= 30
    $healthIssues += "Account-level kill switches triggered"
}
if($groupKills.Count -gt 0) {
    $healthScore -= ($groupKills.Count * 5)
    $healthIssues += "$($groupKills.Count) group kill switches triggered"
}
if($emergencies.Count -gt 10) {
    $healthScore -= 10
    $healthIssues += "Multiple emergency events ($($emergencies.Count))"
}

# Check FTMO safety
if($todayAccountStatus -and $todayAccountStatus.Details -match 'Daily Total:\s*\$?\s*(-?\d+\.?\d*)') {
    $dailyTotal = [double]$matches[1]
    if($dailyTotal -lt -8000) {
        $healthScore -= 40
        $healthIssues += "Daily loss approaching FTMO limit"
    } elseif($dailyTotal -lt -5000) {
        $healthScore -= 20
        $healthIssues += "Daily loss in caution zone"
    }
}

# Ensure score doesn't go below 0
$healthScore = [Math]::Max(0, $healthScore)

# Display score
$scoreColor = if($healthScore -ge 90){'Green'}elseif($healthScore -ge 70){'Yellow'}elseif($healthScore -ge 50){'DarkYellow'}else{'Red'}
Write-Host "  OVERALL HEALTH SCORE: $healthScore/100" -ForegroundColor $scoreColor

if($healthScore -ge 90) {
    Write-Host "  Status: ✅ EXCELLENT - All protections functioning optimally" -ForegroundColor Green
    Write-Host "`n  Protection systems are working as designed:" -ForegroundColor Green
    Write-Host "    • No emergency interventions required" -ForegroundColor Green
    Write-Host "    • FTMO limits well respected" -ForegroundColor Green
    Write-Host "    • DD thresholds preventing excessive losses" -ForegroundColor Green
    Write-Host "    • System operating within normal parameters" -ForegroundColor Green
} elseif($healthScore -ge 70) {
    Write-Host "  Status: ✅ GOOD - Protections working with minor triggers" -ForegroundColor Yellow
} elseif($healthScore -ge 50) {
    Write-Host "  Status: ⚠️  FAIR - Some protection systems activated" -ForegroundColor DarkYellow
} else {
    Write-Host "  Status: 🚨 POOR - Multiple protection breaches" -ForegroundColor Red
}

if($healthIssues.Count -gt 0) {
    Write-Host "`n  Issues Detected:" -ForegroundColor Yellow
    $healthIssues | ForEach-Object {
        Write-Host "    • $_" -ForegroundColor Yellow
    }
}

Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   PROTECTION ANALYSIS COMPLETE                                   ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
